// ignore_for_file: use_null_aware_elements

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/matix_client.dart';
import '../config.dart';
import '../features/apuntes/domain/apunte.dart';
import '../features/apuntes/presentation/apuntes_list_screen.dart';
import '../features/apuntes/presentation/editor_apunte_screen.dart';
import '../features/apuntes/providers/apuntes_providers.dart';
import '../features/busqueda/presentation/busqueda_screen.dart';
import '../features/cursos/domain/curso.dart';
import '../features/cursos/domain/sesion_clase.dart';
import '../features/evaluaciones/domain/evaluacion.dart';
import '../features/eventos/domain/evento.dart';
import '../features/eventos/presentation/calendario_screen.dart';
import '../features/eventos/providers/eventos_providers.dart';
import '../features/matix/data/captura_apunte_repository.dart';
import '../features/matix/data/grabacion_voz_service.dart';
import '../features/matix/data/matix_transcribir_repository.dart';
import '../features/matix/presentation/manos_libres_screen.dart';
import '../features/matix/providers/captura_apunte_providers.dart';
import '../features/proyectos/domain/proyecto.dart';
import '../features/proyectos/presentation/detalle_proyecto_screen.dart';
import '../features/proyectos/providers/proyectos_providers.dart';
import '../features/tareas/domain/tarea.dart';
import '../features/tareas/presentation/nueva_tarea_screen.dart';
import '../features/tareas/providers/tareas_providers.dart';
import '../features/universidad/providers/universidad_providers.dart';
import '../theme/matix_colors.dart';
import '../theme/matix_spacing.dart';
import 'ajustes_screen.dart';
import 'universidad_screen.dart';

// ══════════════════════════════════════════════════════════════════
// Lógica pura del tablero (testeable sin red ni widgets).
// ══════════════════════════════════════════════════════════════════

/// Tareas que entran al bloque "Hoy": sin completar y que vencen hoy
/// o ya vencieron. Ordena vencidas primero, luego por hora de
/// vencimiento ascendente.
///
/// Usa `ahora` para todo el cálculo (en vez de `Tarea.estaVencida`,
/// que lee `DateTime.now()` internamente) para que la función sea
/// determinística en tests.
List<Tarea> tareasDeHoy(List<Tarea> todas, DateTime ahora) {
  bool vencida(Tarea t) => t.venceEn != null && t.venceEn!.isBefore(ahora);
  final out = todas
      .where((t) => !t.completada && (t.venceHoy(ahora) || vencida(t)))
      .toList()
    ..sort((a, b) {
      final av = vencida(a) ? 0 : 1;
      final bv = vencida(b) ? 0 : 1;
      if (av != bv) return av - bv;
      final ae = a.venceEn;
      final be = b.venceEn;
      if (ae == null && be == null) return 0;
      if (ae == null) return 1;
      if (be == null) return -1;
      return ae.compareTo(be);
    });
  return out;
}

/// Los `max` apuntes más recientes por fecha de actualización.
List<Apunte> apuntesRecientes(List<Apunte> todos, {int max = 5}) {
  final out = [...todos]
    ..sort((a, b) => b.actualizadoEn.compareTo(a.actualizadoEn));
  return out.take(max).toList();
}

/// Ideas dormidas candidatas a reflote (Capa 7): apuntes GENERALES (sin
/// proyecto, curso ni cuaderno — las ideas sueltas), no archivados, que
/// llevan [dias]+ días sin tocarse. Las más viejas primero; como mucho
/// [max] para no abrumar. `ahora` se pasa para que sea determinística.
///
/// "Sin tocarse" se mide con `actualizadoEn`, que el cerebro bumpea en
/// cada update: por eso "retomar" (que toca el apunte) lo saca de esta
/// lista, y "archivar" (que setea `archivadoEn`) lo saca para siempre.
List<Apunte> ideasParaReflotar(
  List<Apunte> todos,
  DateTime ahora, {
  int dias = 14,
  int max = 3,
}) {
  final umbral = ahora.subtract(Duration(days: dias));
  final out = todos
      .where((a) =>
          a.archivadoEn == null &&
          a.proyectoId == null &&
          a.cursoId == null &&
          a.cuadernoId == null &&
          !a.actualizadoEn.isAfter(umbral))
      .toList()
    ..sort((a, b) => a.actualizadoEn.compareTo(b.actualizadoEn));
  return out.take(max).toList();
}

/// Un ítem próximo de Universidad: o una clase recurrente, o una
/// entrega/examen. `cuando` es el instante en que ocurre.
@immutable
class ProximoUni {
  const ProximoUni({
    required this.titulo,
    required this.cuando,
    required this.esClase,
    this.cursoNombre,
    this.tipoLabel,
  });

  final String titulo;
  final DateTime cuando;
  final bool esClase;
  final String? cursoNombre;

  /// Para entregas: "Entrega" / "Examen" / … . Null para clases.
  final String? tipoLabel;
}

/// La próxima clase (barriendo los próximos 14 días) o la próxima
/// entrega futura sin nota — la que ocurra antes. `null` si no hay
/// ninguna de las dos.
ProximoUni? proximoUni(
  List<SesionClase> sesiones,
  List<Curso> cursos,
  List<Evaluacion> evaluaciones,
  DateTime ahora,
) {
  final cursosMap = {for (final c in cursos) c.id: c};

  // Próxima clase: el primer día (de hoy en adelante) que tenga una
  // sesión cuya hora de inicio aún no pasó da la clase más próxima.
  ProximoUni? clase;
  for (var i = 0; i < 14; i++) {
    final dia =
        DateTime(ahora.year, ahora.month, ahora.day).add(Duration(days: i));
    for (final s in sesiones) {
      if (!s.ocurreEn(dia)) continue;
      final inicio = s.inicioEn(dia);
      if (!inicio.isAfter(ahora)) continue;
      if (clase == null || inicio.isBefore(clase.cuando)) {
        final curso = cursosMap[s.cursoId];
        clase = ProximoUni(
          titulo: curso?.nombre ?? 'Clase',
          cuando: inicio,
          esClase: true,
          cursoNombre: curso?.nombre,
        );
      }
    }
    if (clase != null) break;
  }

  // Próxima entrega/examen futura y sin nota.
  ProximoUni? entrega;
  for (final e in evaluaciones) {
    if (e.tieneNota) continue;
    if (!e.fecha.isAfter(ahora)) continue;
    if (entrega == null || e.fecha.isBefore(entrega.cuando)) {
      final curso = cursosMap[e.cursoId];
      entrega = ProximoUni(
        titulo: e.titulo,
        cuando: e.fecha,
        esClase: false,
        cursoNombre: curso?.nombre,
        tipoLabel: e.tipo.label,
      );
    }
  }

  if (clase == null) return entrega;
  if (entrega == null) return clase;
  return clase.cuando.isBefore(entrega.cuando) ? clase : entrega;
}

// ══════════════════════════════════════════════════════════════════
// Pantalla
// ══════════════════════════════════════════════════════════════════

class InicioScreen extends ConsumerWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        toolbarHeight: 76,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat("EEEE d 'de' MMMM", 'es').format(ahora),
              style: const TextStyle(
                fontSize: 12,
                color: MatixColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${_saludo(ahora)}, Gian Piero',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: MatixColors.text,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BusquedaScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AjustesScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: MatixColors.accent,
        onRefresh: () async {
          ref.invalidate(proyectosListProvider);
          ref.invalidate(tareasProvider);
          ref.invalidate(eventosProvider);
          ref.invalidate(evaluacionesListProvider);
          ref.invalidate(apuntesListProvider);
          ref.invalidate(sesionesClaseProvider);
          ref.invalidate(cursosListProvider);
        },
        child: ListView(
          // Cubre la nav inferior + safe area + saliente del FAB.
          padding: EdgeInsets.fromLTRB(
            0,
            8,
            0,
            MatixLayout.bottomNavGuard(context),
          ),
          children: const [
            _BotonesRitual(),
            _CapturaApunte(),
            _BloqueHoy(),
            _BloqueApuntesRecientes(),
            _BloqueReflote(),
            _BloqueProyectosActivos(),
            _BloqueUniversidad(),
          ],
        ),
      ),
    );
  }

  String _saludo(DateTime h) {
    if (h.hour < 12) return 'Buenos días';
    if (h.hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }
}

// ─── Botones de ritual: briefing matinal + cierre nocturno ──────
//
// Disparan el modo manos libres con un mensaje seed (el equivalente
// a que el usuario hubiera dicho "buenos días" / "vamos al cierre")
// para que Matix arranque narrando, no escuchando.
//
// Adaptan énfasis visual a la hora del día:
//   - 5:00 a 11:59 → "Buenos días" prominente (gradiente),
//                    "Cierre del día" secundario (outline).
//   - 20:00 a 4:59 → al revés.
//   - El resto del día, ambos secundarios.
class _BotonesRitual extends StatelessWidget {
  const _BotonesRitual();

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final esMatutino = h >= 5 && h < 12;
    final esNoche = h >= 20 || h < 5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _BotonRitual(
              icono: Icons.wb_sunny_outlined,
              etiqueta: 'Buenos días',
              prominente: esMatutino,
              seed: 'Buenos días, dame el briefing.',
              color: MatixColors.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _BotonRitual(
              icono: Icons.nightlight_round,
              etiqueta: 'Cierre del día',
              prominente: esNoche,
              seed: 'Hagamos el cierre del día.',
              color: MatixColors.purple,
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonRitual extends StatelessWidget {
  const _BotonRitual({
    required this.icono,
    required this.etiqueta,
    required this.prominente,
    required this.seed,
    required this.color,
  });

  final IconData icono;
  final String etiqueta;
  final bool prominente;
  final String seed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fondo = prominente
        ? color.withValues(alpha: 0.18)
        : Colors.transparent;
    final borde = prominente
        ? color.withValues(alpha: 0.55)
        : MatixColors.hairline;
    final colorTexto = prominente ? color : MatixColors.text;
    return Material(
      color: fondo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borde),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManosLibresScreen(seedMensaje: seed),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, color: colorTexto, size: 20),
              const SizedBox(width: 10),
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorTexto,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Captura de apunte: "Anota algo…" ───────────────────────────
//
// Captura sin fricción (principio #1 del hub). Dos puertas de entrada:
//
// 1. Texto: lo que escribes se vuelve el título de un apunte general
//    (sin curso). El modelo admite apuntes sin curso, no migra nada.
//
// 2. Voz (Paso C2): tocas el micrófono, dictas, y el cerebro
//    transcribe (Whisper) y guarda el apunte YA CLASIFICADO contra
//    los proyectos/cursos existentes — sin abrir el chat de Matix.
//    El snackbar confirma dónde quedó y deja abrirlo para corregir.
//    Es captura rápida: nada de loop de voz ni TTS.
enum _EstadoCaptura { idle, grabando, procesando }

class _CapturaApunte extends ConsumerStatefulWidget {
  const _CapturaApunte();

  @override
  ConsumerState<_CapturaApunte> createState() => _CapturaApunteState();
}

class _CapturaApunteState extends ConsumerState<_CapturaApunte> {
  final _ctrl = TextEditingController();
  _EstadoCaptura _estado = _EstadoCaptura.idle;

  // Servicios propios (no compartimos el `vozNotifierProvider` del
  // chat: es autoDispose y ambas pantallas viven a la vez en el
  // IndexedStack, así que reusarlo cruzaría estados).
  late final GrabacionVozService _voz;
  late final MatixTranscribirRepository _transcribir;

  @override
  void initState() {
    super.initState();
    _voz = GrabacionVozService();
    _transcribir = MatixTranscribirRepository();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _voz.dispose();
    _transcribir.close();
    super.dispose();
  }

  // ── Texto: apunte general, vía rápida sin clasificar ──
  Future<void> _guardarTexto() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _estado != _EstadoCaptura.idle) return;
    setState(() => _estado = _EstadoCaptura.procesando);
    try {
      await ref.read(apuntesRepoProvider).crear(titulo: texto);
      _ctrl.clear();
      ref.invalidate(apuntesListProvider);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      _mostrar('Apunte guardado');
    } on MatixApiException catch (e) {
      _mostrar('No pude guardar: ${e.message}');
    } catch (e) {
      _mostrar('No pude guardar: $e');
    } finally {
      _aIdle();
    }
  }

  // ── Voz: graba → transcribe → captura clasificada ──
  Future<void> _toggleMic() async {
    if (_estado == _EstadoCaptura.procesando) return;
    if (_estado == _EstadoCaptura.grabando) {
      await _detenerYCapturar();
    } else {
      await _empezarAGrabar();
    }
  }

  Future<void> _empezarAGrabar() async {
    try {
      await _voz.iniciar();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => _estado = _EstadoCaptura.grabando);
    } on PermisoMicDenegado catch (e) {
      _mostrar(e.permanente
          ? 'Necesito el micrófono. Concédelo desde los ajustes del '
              'sistema y vuelve a intentar.'
          : 'Necesito permiso del micrófono para grabar.');
    } catch (e) {
      _mostrar('No pude empezar a grabar: $e');
    }
  }

  Future<void> _detenerYCapturar() async {
    setState(() => _estado = _EstadoCaptura.procesando);

    GrabacionResultado? grab;
    try {
      grab = await _voz.detener();
    } catch (_) {
      grab = null;
    }
    if (grab == null) {
      _aIdle();
      _mostrar('No quedó nada grabado. Intenta de nuevo.');
      return;
    }
    // Tap accidental: audio muy corto. No gastamos Whisper en silencio.
    if (grab.duracion < const Duration(milliseconds: 400)) {
      await _borrar(grab.archivo);
      _aIdle();
      _mostrar('Muy corto. Mantén el micrófono un instante más.');
      return;
    }

    // 1) Transcribir.
    final String texto;
    try {
      texto = await _transcribir.transcribir(grab.archivo);
    } on MatixApiException catch (e) {
      _aIdle();
      _mostrar('No pude transcribir: ${e.message}');
      return;
    } catch (e) {
      _aIdle();
      _mostrar('No pude transcribir: $e');
      return;
    } finally {
      await _borrar(grab.archivo);
    }

    // Whisper devuelve vacío si no escuchó voz real → NO creamos un
    // apunte huérfano; mostramos el problema.
    if (texto.trim().isEmpty) {
      _aIdle();
      _mostrar('No te escuché bien. Intenta de nuevo.');
      return;
    }

    // 2) Capturar clasificado (mismo flujo crear_apunte del Paso C).
    try {
      final apunte =
          await ref.read(capturaApunteRepoProvider).capturar(texto.trim());
      ref.invalidate(apuntesListProvider);
      _aIdle();
      _mostrarGuardado(apunte);
    } on MatixApiException catch (e) {
      _aIdle();
      _mostrar('No pude guardar el apunte: ${e.message}');
    } catch (e) {
      _aIdle();
      _mostrar('No pude guardar el apunte: $e');
    }
  }

  Future<void> _borrar(File archivo) async {
    try {
      await archivo.delete();
    } catch (_) {
      // No crítico: los temporales se limpian solos.
    }
  }

  void _aIdle() {
    if (mounted) setState(() => _estado = _EstadoCaptura.idle);
  }

  void _mostrar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _mostrarGuardado(ApunteCapturado a) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(a.destinoLabel),
          action: SnackBarAction(
            label: 'Abrir',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditorApunteScreen(apunteId: a.id),
              ),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final grabando = _estado == _EstadoCaptura.grabando;
    final procesando = _estado == _EstadoCaptura.procesando;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: grabando ? MatixColors.red : MatixColors.hairline,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
        child: Row(
          children: [
            Icon(
              grabando ? Icons.fiber_manual_record : Icons.edit_note,
              color: grabando ? MatixColors.red : MatixColors.muted,
              size: grabando ? 14 : 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                enabled: _estado == _EstadoCaptura.idle,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _guardarTexto(),
                style: const TextStyle(color: MatixColors.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: grabando
                      ? 'Escuchando… toca para terminar'
                      : 'Anota algo…',
                  hintStyle: TextStyle(
                    color: grabando ? MatixColors.red : MatixColors.muted,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            if (procesando)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: MatixColors.accent,
                  ),
                ),
              )
            else ...[
              IconButton(
                tooltip: grabando ? 'Terminar y guardar' : 'Dictar apunte',
                icon: Icon(grabando ? Icons.stop_rounded : Icons.mic_none),
                color: grabando ? MatixColors.red : MatixColors.muted,
                onPressed: _toggleMic,
              ),
              if (!grabando)
                IconButton(
                  tooltip: 'Guardar apunte',
                  icon: const Icon(Icons.arrow_upward_rounded),
                  color: MatixColors.accent,
                  onPressed: _guardarTexto,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Bloque: Hoy (eventos del día + tareas de hoy/vencidas) ─────
class _BloqueHoy extends ConsumerWidget {
  const _BloqueHoy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = DateTime.now();
    final tareasAsync = ref.watch(tareasProvider);
    final eventosAsync = ref.watch(eventosDelDiaProvider(ahora));

    final eventos = eventosAsync.valueOrNull ?? const <Evento>[];
    final tareas =
        tareasDeHoy(tareasAsync.valueOrNull ?? const <Tarea>[], ahora);
    final total = eventos.length + tareas.length;
    final cargando = !tareasAsync.hasValue || !eventosAsync.hasValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Hoy', count: total == 0 ? null : total),
        if (cargando && total == 0)
          const _LoaderLinea()
        else if (total == 0)
          const _EmptyCard(
            'Hoy no tienes nada agendado. Disfruta el día.',
            icono: Icons.check_circle_outline,
          )
        else ...[
          ...eventos.map((e) => _EventoMini(e: e)),
          ...tareas.map((t) => _TareaMini(t: t)),
        ],
      ],
    );
  }
}

class _EventoMini extends StatelessWidget {
  const _EventoMini({required this.e});
  final Evento e;
  @override
  Widget build(BuildContext context) {
    final hi = e.todoElDia
        ? 'Todo'
        : DateFormat.Hm().format(e.iniciaEn.toLocal());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CalendarioScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    hi,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MatixColors.text,
                    ),
                  ),
                ),
                Container(
                  width: 4,
                  height: 32,
                  decoration: BoxDecoration(
                    color: MatixColors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MatixColors.text,
                    ),
                  ),
                ),
                if (MatixConfig.googleVisible && e.esDeGoogle) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.sync, size: 14, color: MatixColors.muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TareaMini extends ConsumerWidget {
  const _TareaMini({required this.t});
  final Tarea t;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hora = t.venceEn == null
        ? '—'
        : DateFormat.Hm().format(t.venceEn!.toLocal());
    final repo = ref.read(tareasRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NuevaTareaScreen(tareaId: t.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    await repo.marcarCompletada(t.id, completada: true);
                    ref.invalidate(tareasProvider);
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MatixColors.text,
                    ),
                  ),
                ),
                Text(
                  hora,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.estaVencida
                        ? MatixColors.red
                        : MatixColors.muted,
                    fontWeight: t.estaVencida
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bloque: Apuntes recientes ──────────────────────────────────
class _BloqueApuntesRecientes extends ConsumerWidget {
  const _BloqueApuntesRecientes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apuntesAsync = ref.watch(apuntesListProvider);
    final proyectos =
        ref.watch(proyectosListProvider).valueOrNull ?? const <Proyecto>[];
    final cursos =
        ref.watch(cursosListProvider).valueOrNull ?? const <Curso>[];
    final proyMap = {for (final p in proyectos) p.id: p.nombre};
    final cursoMap = {for (final c in cursos) c.id: c.nombre};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          label: 'Apuntes recientes',
          accionLabel: 'Ver todos',
          onAccion: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ApuntesListScreen()),
          ),
        ),
        apuntesAsync.when(
          loading: () => const _LoaderLinea(),
          error: (_, _) => const _EmptyCard('No pude cargar tus apuntes.'),
          data: (lista) {
            final recientes = apuntesRecientes(lista);
            if (recientes.isEmpty) {
              return const _EmptyCard(
                'Aún no tienes apuntes. Escribe algo arriba para empezar.',
                icono: Icons.notes_outlined,
              );
            }
            return Column(
              children: [
                for (final a in recientes)
                  _ApunteMini(
                    apunte: a,
                    chip: proyMap[a.proyectoId] ?? cursoMap[a.cursoId],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ApunteMini extends StatelessWidget {
  const _ApunteMini({required this.apunte, this.chip});
  final Apunte apunte;
  final String? chip;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditorApunteScreen(apunteId: apunte.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        apunte.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text,
                        ),
                      ),
                      if (apunte.contenido.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          apunte.contenido,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MatixColors.muted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (chip != null) ...[
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: MatixColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        chip!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bloque: Reflote de ideas dormidas ──────────────────────────
//
// "Ideas que dejaste pausadas": apuntes generales que llevan rato sin
// tocarse. Sección silenciosa — solo aparece si hay candidatas. Cada
// idea se puede retomar (con opción de pasarla a tarea) o archivar (deja
// de reflotarse para siempre).
class _BloqueReflote extends ConsumerWidget {
  const _BloqueReflote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ideas = ref.watch(apuntesListProvider).maybeWhen(
          data: (lista) => ideasParaReflotar(lista, DateTime.now()),
          orElse: () => const <Apunte>[],
        );
    if (ideas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Ideas que dejaste pausadas'),
        for (final a in ideas) _IdeaReflote(idea: a),
      ],
    );
  }
}

class _IdeaReflote extends ConsumerWidget {
  const _IdeaReflote({required this.idea});
  final Apunte idea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dias = DateTime.now().difference(idea.actualizadoEn).inDays;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditorApunteScreen(apunteId: idea.id),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idea.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      ),
                    ),
                    if (idea.contenido.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        idea.contenido,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MatixColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      dias <= 0
                          ? 'Pausada hace poco'
                          : 'Pausada hace $dias ${dias == 1 ? "día" : "días"}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: MatixColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _retomar(context, ref),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retomar'),
                    style: TextButton.styleFrom(
                      foregroundColor: MatixColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _archivar(context, ref),
                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                    label: const Text('Archivar'),
                    style: TextButton.styleFrom(
                      foregroundColor: MatixColors.muted,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Retomar": abre una hoja con la opción de convertir en tarea o solo
  /// quitarla del reflote. Ambas marcan el apunte como tocado.
  Future<void> _retomar(BuildContext context, WidgetRef ref) async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MatixColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.checklist_outlined,
                  color: MatixColors.accent),
              title: const Text('Convertir en tarea'),
              subtitle: const Text('La paso a tu lista de tareas'),
              onTap: () => Navigator.pop(ctx, 'tarea'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline,
                  color: MatixColors.accent),
              title: const Text('Solo quitarla del reflote'),
              subtitle: const Text('La marco como vista; vuelve si la dejas '
                  'dormir otra vez'),
              onTap: () => Navigator.pop(ctx, 'tocar'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (opcion == null || !context.mounted) return;
    if (opcion == 'tarea') {
      await _convertirEnTarea(context, ref);
    } else {
      await _soloRetomar(context, ref);
    }
  }

  Future<void> _soloRetomar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apuntesRepoProvider).retomar(idea.id);
      ref.invalidate(apuntesListProvider);
      if (context.mounted) {
        _mostrar(context, 'Listo, la quitamos del reflote por ahora.');
      }
    } catch (e) {
      if (context.mounted) _mostrar(context, 'No pude retomarla: $e');
    }
  }

  Future<void> _convertirEnTarea(BuildContext context, WidgetRef ref) async {
    try {
      final tarea =
          await ref.read(tareasRepositoryProvider).crear(titulo: idea.titulo);
      // Convertir cuenta como retomar: la idea sale del reflote.
      await ref.read(apuntesRepoProvider).retomar(idea.id);
      ref.invalidate(tareasProvider);
      ref.invalidate(apuntesListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Tarea creada.'),
            action: SnackBarAction(
              label: 'Editar',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NuevaTareaScreen(tareaId: tarea.id),
                ),
              ),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted) _mostrar(context, 'No pude crear la tarea: $e');
    }
  }

  Future<void> _archivar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apuntesRepoProvider).archivar(idea.id);
      ref.invalidate(apuntesListProvider);
      if (context.mounted) {
        _mostrar(context, 'Archivada. No volverá a aparecer.');
      }
    } catch (e) {
      if (context.mounted) _mostrar(context, 'No pude archivar: $e');
    }
  }

  void _mostrar(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }
}

// ─── Bloque: Proyectos activos (máx 3) ──────────────────────────
class _BloqueProyectosActivos extends ConsumerWidget {
  const _BloqueProyectosActivos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proysAsync = ref.watch(proyectosListProvider);
    final tareas = ref.watch(tareasProvider).valueOrNull ?? const <Tarea>[];
    final tareaTitulo = {for (final t in tareas) t.id: t.titulo};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Proyectos activos'),
        proysAsync.when(
          loading: () => const _LoaderLinea(),
          error: (_, _) => const _EmptyCard('No pude cargar tus proyectos.'),
          data: (lista) {
            final activos = lista
                .where((p) => p.estado == EstadoProyecto.activo)
                .toList()
              ..sort((a, b) =>
                  (a.prioridad ?? 99).compareTo(b.prioridad ?? 99));
            final top = activos.take(3).toList();
            if (top.isEmpty) {
              return const _EmptyCard(
                'Sin proyectos activos. Crea uno desde la pestaña Proyectos.',
                icono: Icons.flag_outlined,
              );
            }
            return SizedBox(
              height: 132,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: top.length,
                itemBuilder: (_, i) {
                  final p = top[i];
                  final proxima = p.tareaSiguienteId == null
                      ? null
                      : tareaTitulo[p.tareaSiguienteId];
                  return _ProyectoMini(p: p, proximaAccion: proxima);
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ProyectoMini extends StatelessWidget {
  const _ProyectoMini({required this.p, this.proximaAccion});
  final Proyecto p;
  final String? proximaAccion;
  @override
  Widget build(BuildContext context) {
    final calorColor = p.enRiesgo ? MatixColors.red : MatixColors.green;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetalleProyectoScreen(proyectoId: p.id),
        ),
      ),
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: MatixColors.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: MatixColors.accent.withValues(alpha: 0.18),
                    border: Border.all(
                        color: MatixColors.accent.withValues(alpha: 0.45)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: Text('#${p.prioridad ?? "-"}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: MatixColors.accent,
                      )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MatixColors.text,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: calorColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    p.enRiesgo
                        ? '${p.etiquetaCalor.toUpperCase()}·RIESGO'
                        : p.etiquetaCalor.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: calorColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(child: _detalle()),
          ],
        ),
      ),
    );
  }

  Widget _detalle() {
    if (proximaAccion != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.arrow_right_alt,
                size: 15, color: MatixColors.accent),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              proximaAccion!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: MatixColors.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      );
    }
    if (p.lineaMeta != null && p.lineaMeta!.isNotEmpty) {
      return Text(
        p.lineaMeta!,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          color: MatixColors.muted,
          height: 1.4,
        ),
      );
    }
    return Text(
      'Sin acción siguiente. Tócalo para definirla.',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: MatixColors.muted.withValues(alpha: 0.8),
        height: 1.4,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

// ─── Bloque: Universidad (próxima clase o entrega) ──────────────
class _BloqueUniversidad extends ConsumerWidget {
  const _BloqueUniversidad();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesiones =
        ref.watch(sesionesClaseProvider).valueOrNull ?? const <SesionClase>[];
    final cursos =
        ref.watch(cursosListProvider).valueOrNull ?? const <Curso>[];
    final evals = ref.watch(evaluacionesListProvider).valueOrNull ??
        const <Evaluacion>[];
    final prox = proximoUni(sesiones, cursos, evals, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          label: 'Universidad',
          accionLabel: 'Abrir',
          onAccion: () => _abrir(context),
        ),
        if (prox == null)
          const _EmptyCard(
            'Sin clases ni entregas próximas.',
            icono: Icons.school_outlined,
          )
        else
          _UniMini(prox: prox, onTap: () => _abrir(context)),
      ],
    );
  }

  void _abrir(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UniversidadScreen()),
      );
}

class _UniMini extends StatelessWidget {
  const _UniMini({required this.prox, required this.onTap});
  final ProximoUni prox;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat("EEE d MMM · HH:mm", 'es')
        .format(prox.cuando.toLocal());
    final color = prox.esClase ? MatixColors.teal : MatixColors.accent;
    final etiqueta =
        prox.esClase ? 'CLASE' : (prox.tipoLabel ?? 'Entrega').toUpperCase();
    final subtitulo = [
      if (!prox.esClase && prox.cursoNombre != null) prox.cursoNombre!,
      fecha,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    etiqueta,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prox.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text,
                        ),
                      ),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: MatixColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: MatixColors.muted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Piezas compartidas ─────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    this.count,
    this.accionLabel,
    this.onAccion,
  });
  final String label;
  final int? count;
  final String? accionLabel;
  final VoidCallback? onAccion;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: MatixColors.muted,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MatixColors.muted,
              ),
            ),
          ],
          const Spacer(),
          if (accionLabel != null && onAccion != null)
            GestureDetector(
              onTap: onAccion,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  accionLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MatixColors.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoaderLinea extends StatelessWidget {
  const _LoaderLinea();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: MatixColors.accent,
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.texto, {this.icono});
  final String texto;
  final IconData? icono;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MatixColors.hairline),
        ),
        child: Row(
          children: [
            if (icono != null) ...[
              Icon(icono, color: MatixColors.muted, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  fontSize: 13,
                  color: MatixColors.muted,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

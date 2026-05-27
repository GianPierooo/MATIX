// ignore_for_file: use_null_aware_elements

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../features/apuntes/presentation/apuntes_list_screen.dart';
import '../features/busqueda/presentation/busqueda_screen.dart';
import '../features/cierre/presentation/cierre_dia_screen.dart';
import '../features/eventos/domain/evento.dart';
import '../features/eventos/presentation/calendario_screen.dart';
import '../features/eventos/providers/eventos_providers.dart';
import '../features/evaluaciones/domain/evaluacion.dart';
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
            tooltip: 'Calendario',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CalendarioScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Apuntes',
            icon: const Icon(Icons.note_alt_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ApuntesListScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Cierre del día',
            icon: const Icon(Icons.nightlight_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CierreDiaScreen()),
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
            _BloqueProyectos(),
            _BloqueParaHoy(),
            _BloqueProximasEntregas(),
            _BloqueTuDia(),
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

// ─── Bloque: Tus 3 proyectos activos ────────────────────────────
class _BloqueProyectos extends ConsumerWidget {
  const _BloqueProyectos();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proys = ref.watch(proyectosListProvider);
    return proys.when(
      loading: () => const SizedBox(height: 110),
      error: (_, _) => const SizedBox.shrink(),
      data: (lista) {
        final activos = lista
            .where((p) => p.estado == EstadoProyecto.activo)
            .toList()
          ..sort((a, b) =>
              (a.prioridad ?? 99).compareTo(b.prioridad ?? 99));
        if (activos.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(
                label: 'Tus ${activos.length} proyectos activos'),
            SizedBox(
              height: 122,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: activos.length,
                itemBuilder: (_, i) => _ProyectoMini(p: activos[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProyectoMini extends StatelessWidget {
  const _ProyectoMini({required this.p});
  final Proyecto p;
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
          border: Border.all(
              color: MatixColors.accent.withValues(alpha: 0.35)),
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
                        color:
                            MatixColors.accent.withValues(alpha: 0.45)),
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
            if (p.lineaMeta != null) ...[
              const SizedBox(height: 10),
              Text(
                p.lineaMeta!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: MatixColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Bloque: Para hoy ────────────────────────────────────────────
class _BloqueParaHoy extends ConsumerWidget {
  const _BloqueParaHoy();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tareas = ref.watch(tareasProvider);
    return tareas.when(
      loading: () => const SizedBox(height: 60),
      error: (_, _) => const SizedBox.shrink(),
      data: (lista) {
        final ahora = DateTime.now();
        final hoy = lista
            .where((t) => !t.completada && t.venceHoy(ahora))
            .toList()
          ..sort((a, b) => a.venceEn!.compareTo(b.venceEn!));
        if (hoy.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(label: 'Para hoy', count: hoy.length),
            ...hoy.take(5).map((t) => _TareaMini(t: t)),
          ],
        );
      },
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

// ─── Bloque: Próximas entregas (evaluaciones) ───────────────────
class _BloqueProximasEntregas extends ConsumerWidget {
  const _BloqueProximasEntregas();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evs = ref.watch(evaluacionesListProvider);
    final cursos = ref.watch(cursosListProvider);
    return evs.when(
      loading: () => const SizedBox(height: 60),
      error: (_, _) => const SizedBox.shrink(),
      data: (lista) {
        final ahora = DateTime.now();
        final futuras = lista
            .where((e) => !e.tieneNota && e.fecha.isAfter(ahora))
            .toList()
          ..sort((a, b) => a.fecha.compareTo(b.fecha));
        if (futuras.isEmpty) return const SizedBox.shrink();
        final mapaCursos = {
          for (final c in cursos.valueOrNull ?? []) c.id: c.nombre,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(
                label: 'Próximas entregas', count: futuras.length),
            ...futuras
                .take(4)
                .map((e) => _EvalMini(eval: e, curso: mapaCursos[e.cursoId])),
          ],
        );
      },
    );
  }
}

class _EvalMini extends StatelessWidget {
  const _EvalMini({required this.eval, this.curso});
  final Evaluacion eval;
  final String? curso;
  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat("EEE d MMM HH:mm", 'es')
        .format(eval.fecha.toLocal());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: MatixColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                eval.tipo.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MatixColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eval.titulo,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      )),
                  Text(
                    [if (curso != null) curso!, fecha].join(' · '),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: MatixColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bloque: Tu día (eventos de hoy) ────────────────────────────
class _BloqueTuDia extends ConsumerWidget {
  const _BloqueTuDia();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventos = ref.watch(eventosDelDiaProvider(DateTime.now()));
    return eventos.when(
      loading: () => const SizedBox(height: 60),
      error: (_, _) => const SizedBox.shrink(),
      data: (lista) {
        if (lista.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(label: 'Tu día', count: lista.length),
            ...lista.take(5).map((e) => _EventoMini(e: e)),
          ],
        );
      },
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MatixColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.count});
  final String label;
  final int? count;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
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
        ],
      ),
    );
  }
}

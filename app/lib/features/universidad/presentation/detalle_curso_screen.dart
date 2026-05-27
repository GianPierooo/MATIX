import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../../cursos/domain/curso.dart';
import '../../cursos/domain/sesion_clase.dart';
import '../../evaluaciones/domain/evaluacion.dart';
import '../providers/universidad_providers.dart';
import 'nueva_evaluacion_screen.dart';
import 'sesion_clase_dialog.dart';

class DetalleCursoScreen extends ConsumerWidget {
  const DetalleCursoScreen({super.key, required this.cursoId});
  final String cursoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursos = ref.watch(cursosListProvider);
    final evs = ref.watch(evaluacionesDeCursoProvider(cursoId));

    final curso = cursos.maybeWhen(
      data: (xs) => xs.firstWhere(
        (c) => c.id == cursoId,
        orElse: () => Curso(
          id: cursoId,
          nombre: 'Curso',
          creadoEn: DateTime.now(),
          actualizadoEn: DateTime.now(),
        ),
      ),
      orElse: () => Curso(
        id: cursoId,
        nombre: 'Curso',
        creadoEn: DateTime.now(),
        actualizadoEn: DateTime.now(),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(curso.nombre),
        actions: [
          IconButton(
            tooltip: 'Nueva evaluación',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NuevaEvaluacionScreen(cursoId: cursoId),
              ),
            ),
          ),
        ],
      ),
      body: evs.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (lista) {
          final promedio = promedioCurso(lista);
          final proximas = lista
              .where((e) =>
                  !e.tieneNota && e.fecha.isAfter(DateTime.now()))
              .toList();
          final pasadas = lista
              .where((e) =>
                  e.tieneNota || e.fecha.isBefore(DateTime.now()))
              .toList()
            ..sort((a, b) => b.fecha.compareTo(a.fecha));
          final sesiones = ref.watch(sesionesDeCursoProvider(cursoId));
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
            children: [
              if (curso.profesor != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Profesor/a · ${curso.profesor}',
                    style: const TextStyle(color: MatixColors.muted),
                  ),
                ),

              _SeccionHorario(cursoId: cursoId, sesiones: sesiones),
              if (promedio != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MatixColors.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rate_rounded,
                          color: MatixColors.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PROMEDIO ACTUAL',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: MatixColors.muted,
                                  letterSpacing: 1.0,
                                )),
                            const SizedBox(height: 4),
                            Text(
                              promedio.toStringAsFixed(2),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: MatixColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              if (proximas.isNotEmpty)
                const _Section('Próximas evaluaciones'),
              ...proximas.map((e) => _EvalRow(eval: e)),

              if (pasadas.isNotEmpty) const _Section('Historial'),
              ...pasadas.map((e) => _EvalRow(eval: e)),

              if (lista.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Aún no hay evaluaciones para este curso.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MatixColors.muted),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SeccionHorario extends ConsumerWidget {
  const _SeccionHorario({required this.cursoId, required this.sesiones});
  final String cursoId;
  final List<SesionClase> sesiones;

  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  Future<void> _agregar(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SesionClaseDialog(cursoId: cursoId),
    );
  }

  Future<void> _borrar(WidgetRef ref, String sesionId) async {
    await ref.read(cursosRepoProvider).borrarSesion(sesionId);
    ref.invalidate(sesionesClaseProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'HORARIO',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: MatixColors.muted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Añadir sesión',
                onPressed: () => _agregar(context),
                icon: const Icon(Icons.add, size: 20),
              ),
            ],
          ),
        ),
        if (sesiones.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Text(
              'Sin sesiones recurrentes. Añade una para que aparezca '
              'en el calendario automáticamente.',
              style: TextStyle(
                fontSize: 12.5,
                color: MatixColors.muted,
                height: 1.4,
              ),
            ),
          ),
        ...sesiones.map(
          (s) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: MatixColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: MatixColors.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _dias[s.diaSemana],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: MatixColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s.horaInicio.substring(0, 5)} – ${s.horaFin.substring(0, 5)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: MatixColors.text,
                          ),
                        ),
                        if (s.ubicacion != null)
                          Text(s.ubicacion!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: MatixColors.muted,
                              )),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.delete_outline,
                        color: MatixColors.red, size: 20),
                    onPressed: () => _borrar(ref, s.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: MatixColors.muted,
          ),
        ),
      );
}

class _EvalRow extends StatelessWidget {
  const _EvalRow({required this.eval});
  final Evaluacion eval;
  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat("EEE d MMM HH:mm", 'es')
        .format(eval.fecha.toLocal());
    final esVencida =
        !eval.tieneNota && eval.fecha.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
          border: esVencida
              ? Border.all(color: MatixColors.red.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: MatixColors.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                eval.tipo.label,
                style: const TextStyle(
                  fontSize: 11,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    fecha,
                    style: TextStyle(
                      fontSize: 12,
                      color: esVencida ? MatixColors.red : MatixColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (eval.tieneNota)
              Text(
                '${eval.notaObtenida!.toStringAsFixed(1)}'
                ' / ${(eval.notaMaxima ?? 20).toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MatixColors.green,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

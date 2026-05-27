import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../domain/bloque_protegido.dart';
import '../domain/proyecto.dart';
import '../providers/proyectos_providers.dart';
import 'selector_accion_siguiente.dart';

class DetalleProyectoScreen extends ConsumerWidget {
  const DetalleProyectoScreen({super.key, required this.proyectoId});
  final String proyectoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(proyectoProvider(proyectoId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proyecto'),
        actions: [
          IconButton(
            tooltip: 'Borrar',
            icon: const Icon(Icons.delete_outline, color: MatixColors.red),
            onPressed: () => _confirmarBorrar(context, ref),
          ),
        ],
      ),
      body: p.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => Center(
          child: Text(
            e is MatixApiException ? e.message : e.toString(),
            textAlign: TextAlign.center,
          ),
        ),
        data: (proy) => _Cuerpo(proyecto: proy),
      ),
    );
  }

  Future<void> _confirmarBorrar(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar proyecto'),
        content: const Text(
            'Las tareas, apuntes y eventos asociados se quedan sin proyecto '
            '(no se borran). ¿Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MatixColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(proyectosRepositoryProvider).borrar(proyectoId);
    ref.invalidate(proyectosListProvider);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _Cuerpo extends ConsumerWidget {
  const _Cuerpo({required this.proyecto});
  final Proyecto proyecto;

  Future<void> _cambiarEstado(
      BuildContext context, WidgetRef ref, EstadoProyecto nuevo) async {
    try {
      await ref
          .read(proyectosRepositoryProvider)
          .cambiarEstado(proyecto.id, nuevo);
      ref.invalidate(proyectosListProvider);
      ref.invalidate(proyectoProvider(proyecto.id));
    } on MatixApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calorColor =
        proyecto.enRiesgo ? MatixColors.red : MatixColors.green;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    label: Text(
                      '${proyecto.estado.label}'
                      '${proyecto.prioridad != null ? ' · #${proyecto.prioridad}' : ''}',
                    ),
                    backgroundColor:
                        MatixColors.accent.withValues(alpha: 0.14),
                    side: BorderSide(
                        color: MatixColors.accent.withValues(alpha: 0.35)),
                    labelStyle: const TextStyle(color: MatixColors.accent),
                  ),
                  Chip(
                    label: Text(proyecto.enRiesgo
                        ? '${proyecto.etiquetaCalor} · RIESGO'
                        : proyecto.etiquetaCalor),
                    backgroundColor: calorColor.withValues(alpha: 0.14),
                    side: BorderSide(
                        color: calorColor.withValues(alpha: 0.35)),
                    labelStyle: TextStyle(color: calorColor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                proyecto.nombre,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                  color: MatixColors.text,
                ),
              ),
              if (proyecto.descripcion != null) ...[
                const SizedBox(height: 6),
                Text(
                  proyecto.descripcion!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: MatixColors.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),

        _BloqueAccionSiguiente(proyecto: proyecto),

        if (proyecto.lineaMeta != null)
          _BloqueInfo(
            titulo: 'LÍNEA DE META',
            cuerpo: proyecto.lineaMeta!,
          ),

        _BloqueInfo(
          titulo: 'ÚLTIMA ACTIVIDAD',
          cuerpo:
              DateFormat("EEEE d 'de' MMMM 'a las' HH:mm", 'es').format(
            proyecto.ultimaActividadEn.toLocal(),
          ),
        ),

        if (proyecto.inactivoDesde != null)
          _BloqueInfo(
            titulo: 'INACTIVO DESDE',
            cuerpo: DateFormat("d MMM yyyy", 'es')
                .format(proyecto.inactivoDesde!.toLocal()),
            color: MatixColors.amber,
          ),

        // Bloque protegido: ventana de tiempo semanal que el usuario
        // reserva para este proyecto. Si está definido lo mostramos
        // como referencia visible (la BD lo guarda en JSONB).
        if (BloqueProtegido.parse(proyecto.bloqueProtegido) != null)
          _BloqueInfo(
            titulo: 'BLOQUE PROTEGIDO',
            cuerpo:
                BloqueProtegido.parse(proyecto.bloqueProtegido)!.legible(),
            color: MatixColors.accent,
          ),

        // Acciones de estado
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              if (proyecto.estado != EstadoProyecto.activo)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _cambiarEstado(
                        context, ref, EstadoProyecto.activo),
                    icon: const Icon(Icons.play_arrow_rounded,
                        color: MatixColors.green),
                    label: const Text('Activar'),
                  ),
                ),
              if (proyecto.estado == EstadoProyecto.activo) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _cambiarEstado(
                        context, ref, EstadoProyecto.aparcado),
                    icon: const Icon(Icons.pause_circle_outline,
                        color: MatixColors.amber),
                    label: const Text('Aparcar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _cambiarEstado(
                        context, ref, EstadoProyecto.terminado),
                    icon: const Icon(Icons.check_circle_outline,
                        color: MatixColors.green),
                    label: const Text('Terminar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bloque destacado de "Acción siguiente" del proyecto.
///
/// - Si el proyecto tiene `tarea_siguiente_id`: muestra la tarea y
///   ofrece dos acciones: "Marcar hecha → ¿siguiente?" y "Cambiar".
/// - Si no la tiene: muestra un botón grande "Definir acción
///   siguiente" que abre el selector.
class _BloqueAccionSiguiente extends ConsumerWidget {
  const _BloqueAccionSiguiente({required this.proyecto});
  final Proyecto proyecto;

  Future<void> _abrirSelector(BuildContext context, WidgetRef ref) async {
    final res = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MatixColors.cardHi,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SelectorAccionSiguiente(proyectoId: proyecto.id),
    );
    if (res == null) return;
    // res == '' significa "quitar"; res no vacío = id de tarea.
    final repo = ref.read(proyectosRepositoryProvider);
    try {
      await repo.actualizar(
        proyecto.id,
        {'tarea_siguiente_id': res.isEmpty ? null : res},
      );
      ref.invalidate(proyectosListProvider);
      ref.invalidate(proyectoProvider(proyecto.id));
    } on MatixApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _marcarHecha(BuildContext context, WidgetRef ref) async {
    final tareaId = proyecto.tareaSiguienteId;
    if (tareaId == null) return;
    final tareasRepo = ref.read(tareasRepositoryProvider);
    try {
      await tareasRepo.marcarCompletada(tareaId, completada: true);
      ref.invalidate(tareasProvider);
      // Limpiar la acción siguiente del proyecto y abrir el selector
      // para que el usuario elija la próxima.
      await ref
          .read(proyectosRepositoryProvider)
          .actualizar(proyecto.id, {'tarea_siguiente_id': null});
      ref.invalidate(proyectoProvider(proyecto.id));
      ref.invalidate(proyectosListProvider);
      if (context.mounted) {
        await _abrirSelector(context, ref);
      }
    } on MatixApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tareaId = proyecto.tareaSiguienteId;
    final tarea = tareaId == null
        ? null
        : ref.watch(tareaPorIdProvider(tareaId));
    final accentColor = proyecto.esActivo
        ? MatixColors.accent
        : MatixColors.muted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tarea == null
              ? MatixColors.card
              : accentColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: tarea == null
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.04))
              : Border.all(color: accentColor.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ACCIÓN SIGUIENTE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: tarea == null ? MatixColors.muted : accentColor,
              ),
            ),
            const SizedBox(height: 8),
            if (tarea == null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _abrirSelector(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Definir acción siguiente'),
                ),
              )
            else ...[
              Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.55),
                        width: 1.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tarea.titulo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _marcarHecha(context, ref),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Marcar hecha'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _abrirSelector(context, ref),
                      child: const Text('Cambiar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BloqueInfo extends StatelessWidget {
  const _BloqueInfo({required this.titulo, required this.cuerpo, this.color});
  final String titulo;
  final String cuerpo;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: color ?? MatixColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cuerpo,
              style: const TextStyle(
                fontSize: 14,
                color: MatixColors.text,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

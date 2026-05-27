import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../../tareas/domain/tarea.dart';
import '../../tareas/providers/tareas_providers.dart';

/// Bottom sheet que muestra las tareas del proyecto y deja al usuario
/// elegir cuál será la "acción siguiente". Devuelve `tareaId` (o
/// `null` si se cierra sin elegir).
class SelectorAccionSiguiente extends ConsumerWidget {
  const SelectorAccionSiguiente({super.key, required this.proyectoId});
  final String proyectoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tareas = ref.watch(tareasDeProyectoProvider(proyectoId));
    final pendientes = tareas.where((t) => !t.completada).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 0, 8),
              child: Text(
                'Elegir acción siguiente',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: MatixColors.text,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 0, 12),
              child: Text(
                'La tarea que elijas será visible en el detalle del '
                'proyecto y en el Inicio. Es la "siguiente cosa concreta".',
                style: TextStyle(fontSize: 12.5, color: MatixColors.muted),
              ),
            ),
            if (pendientes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Este proyecto no tiene tareas pendientes.\n'
                    'Crea una desde la pestaña Tareas y vuelve aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: MatixColors.muted,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pendientes.length,
                  itemBuilder: (_, i) => _TareaTile(t: pendientes[i]),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop<String?>(null),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop<String?>(''),
                    child: const Text('Quitar siguiente'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TareaTile extends StatelessWidget {
  const _TareaTile({required this.t});
  final Tarea t;
  @override
  Widget build(BuildContext context) {
    final vence = t.venceEn == null
        ? '—'
        : DateFormat("EEE d MMM HH:mm", 'es').format(t.venceEn!.toLocal());
    final color = t.estaVencida ? MatixColors.red : MatixColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop<String?>(t.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _colorPrio(t.prioridad),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.titulo,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MatixColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vence,
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: MatixColors.muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _colorPrio(Prioridad p) => switch (p) {
      Prioridad.alta => MatixColors.red,
      Prioridad.media => MatixColors.amber,
      Prioridad.baja => MatixColors.accent,
    };

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../tareas/presentation/nueva_tarea_screen.dart';
import '../data/repaso_repository.dart';
import '../providers/repaso_providers.dart';

/// Repaso semanal con Matix (Capa 8 · Repaso): el cierre del día pero
/// semanal y estratégico. Matix sintetiza la semana (balance honesto,
/// sin reproche) y desde acá puedes accionar lo que se pasó.
class RepasoSemanalScreen extends ConsumerWidget {
  const RepasoSemanalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(repasoSemanalProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Repaso de la semana')),
      body: async.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: MatixColors.accent),
              SizedBox(height: MatixSpacing.l),
              Text('Matix está repasando tu semana…',
                  style: TextStyle(color: MatixColors.muted, fontSize: 13)),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(MatixSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No pude armar tu repaso.',
                    textAlign: TextAlign.center),
                const SizedBox(height: MatixSpacing.l),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(repasoSemanalProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MatixColors.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (r) => _Contenido(repaso: r),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.repaso});
  final RepasoSemanal repaso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        // Síntesis de Matix.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(MatixSpacing.l),
          decoration: BoxDecoration(
            color: MatixColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            repaso.resumen,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: MatixColors.text,
            ),
          ),
        ),
        const SizedBox(height: MatixSpacing.l),
        // Números de la semana.
        Row(
          children: [
            _Stat(label: 'Hechas', valor: repaso.completadas.toString()),
            _Stat(label: 'Eventos', valor: repaso.eventos.toString()),
            _Stat(label: 'Apuntes', valor: repaso.apuntesNuevos.toString()),
            _Stat(label: 'Se pasaron', valor: repaso.vencidas.length.toString()),
          ],
        ),

        if (repaso.focos.isNotEmpty) ...[
          const _Titulo('Focos para la próxima semana'),
          for (final f in repaso.focos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.adjust, size: 16, color: MatixColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(f,
                        style: const TextStyle(
                            fontSize: 14, color: MatixColors.text)),
                  ),
                ],
              ),
            ),
        ],

        if (repaso.vencidas.isNotEmpty) ...[
          const _Titulo('Lo que se pasó'),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Sin drama: reprográmalo o suéltalo.',
              style: TextStyle(fontSize: 12.5, color: MatixColors.muted),
            ),
          ),
          for (final v in repaso.vencidas)
            _VencidaTile(
              vencida: v,
              onReprogramar: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NuevaTareaScreen(tareaId: v.id),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.valor});
  final String label;
  final String valor;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(valor,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: MatixColors.accent)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: MatixColors.muted)),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 0, 6),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: MatixColors.muted,
        ),
      ),
    );
  }
}

class _VencidaTile extends StatelessWidget {
  const _VencidaTile({required this.vencida, required this.onReprogramar});
  final TareaVencidaRepaso vencida;
  final VoidCallback onReprogramar;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vencida.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MatixColors.text,
                    ),
                  ),
                  if (vencida.contexto != null &&
                      vencida.contexto!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      vencida.contexto!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: MatixColors.muted),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: onReprogramar,
              style: TextButton.styleFrom(foregroundColor: MatixColors.accent),
              child: const Text('Reprogramar'),
            ),
          ],
        ),
      ),
    );
  }
}

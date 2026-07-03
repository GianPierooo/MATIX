import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_button_styles.dart';
import '../../../theme/matix_spacing.dart';
import '../application/desglose_controller.dart';
import '../domain/paso_propuesto.dart';

/// "Desglosar con Matix" (Capa 7): muestra los pasos propuestos para
/// revisar (editar / quitar / reordenar / cambiar horizonte) y crear.
/// Nada se crea sin confirmar. Si la tarea ya es atómica, lo dice.
class DesglosarScreen extends ConsumerStatefulWidget {
  const DesglosarScreen({
    super.key,
    required this.titulo,
    this.nota,
    this.proyectoId,
    this.cursoId,
  });

  final String titulo;
  final String? nota;
  final String? proyectoId;
  final String? cursoId;

  @override
  ConsumerState<DesglosarScreen> createState() => _DesglosarScreenState();
}

class _DesglosarScreenState extends ConsumerState<DesglosarScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = ref.read(desgloseControllerProvider.notifier)..reiniciar();
      ctrl.desglosar(
        titulo: widget.titulo,
        nota: widget.nota,
        proyectoId: widget.proyectoId,
        cursoId: widget.cursoId,
      );
    });
  }

  void _reintentar() {
    ref.read(desgloseControllerProvider.notifier).desglosar(
          titulo: widget.titulo,
          nota: widget.nota,
          proyectoId: widget.proyectoId,
          cursoId: widget.cursoId,
        );
  }

  Future<void> _editarTitulo(int i, String actual) async {
    final ctrl = TextEditingController(text: actual);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar paso'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Título del paso'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nuevo != null && nuevo.isNotEmpty) {
      ref.read(desgloseControllerProvider.notifier).editarTitulo(i, nuevo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(desgloseControllerProvider);
    final ctrl = ref.read(desgloseControllerProvider.notifier);

    ref.listen<EstadoDesglose>(desgloseControllerProvider, (prev, next) {
      if (prev?.fase == next.fase) return;
      if (next.fase == FaseDesglose.creado) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Listo: ${next.creados} '
                '${next.creados == 1 ? "paso creado" : "pasos creados"}.'),
          ),
        );
        Navigator.of(context).pop();
      } else if (next.fase == FaseDesglose.revision && next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Desglosar con Matix')),
      body: switch (estado.fase) {
        FaseDesglose.inicial || FaseDesglose.desglosando => const _Cargando(),
        FaseDesglose.error => _ErrorVista(
            mensaje: estado.error ?? 'Algo falló.',
            onReintentar: _reintentar,
          ),
        _ => estado.esAtomica || estado.pasos.isEmpty
            ? const _Atomica()
            : _Revision(
                pasos: estado.pasos,
                creando: estado.fase == FaseDesglose.creando,
                onEditar: _editarTitulo,
                onHorizonte: ctrl.cambiarHorizonte,
                onQuitar: ctrl.quitar,
                onReordenar: ctrl.reordenar,
                onCrear: ctrl.crear,
              ),
      },
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: MatixColors.accent),
          SizedBox(height: MatixSpacing.l),
          Text('Partiendo la tarea en pasos…',
              style: TextStyle(color: MatixColors.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Atomica extends StatelessWidget {
  const _Atomica();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MatixSpacing.xl4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                color: MatixColors.green, size: 48),
            const SizedBox(height: MatixSpacing.l),
            const Text(
              'Esto ya es accionable, no hay qué desglosar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: MatixColors.text),
            ),
            const SizedBox(height: MatixSpacing.xl),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorVista extends StatelessWidget {
  const _ErrorVista({required this.mensaje, required this.onReintentar});
  final String mensaje;
  final VoidCallback onReintentar;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MatixSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: MatixSpacing.l),
            FilledButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
              style: MatixButtonStyles.primario,
            ),
          ],
        ),
      ),
    );
  }
}

class _Revision extends StatelessWidget {
  const _Revision({
    required this.pasos,
    required this.creando,
    required this.onEditar,
    required this.onHorizonte,
    required this.onQuitar,
    required this.onReordenar,
    required this.onCrear,
  });

  final List<PasoPropuesto> pasos;
  final bool creando;
  final void Function(int indice, String actual) onEditar;
  final void Function(int indice, Horizonte h) onHorizonte;
  final void Function(int indice) onQuitar;
  final void Function(int oldIndex, int newIndex) onReordenar;
  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            'Revisa los pasos. Mantén presionado para reordenar.',
            style: TextStyle(fontSize: 13, color: MatixColors.muted),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: pasos.length,
            onReorder: onReordenar,
            itemBuilder: (context, i) {
              final p = pasos[i];
              return _PasoTile(
                key: ValueKey('paso_${i}_${p.titulo}'),
                indice: i,
                paso: p,
                onEditar: () => onEditar(i, p.titulo),
                onHorizonte: (h) => onHorizonte(i, h),
                onQuitar: () => onQuitar(i),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FilledButton.icon(
              onPressed: (creando || pasos.isEmpty) ? null : onCrear,
              icon: creando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.add_task, size: 18),
              label: Text('Crear ${pasos.length} '
                  '${pasos.length == 1 ? "paso" : "pasos"}'),
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PasoTile extends StatelessWidget {
  const _PasoTile({
    super.key,
    required this.indice,
    required this.paso,
    required this.onEditar,
    required this.onHorizonte,
    required this.onQuitar,
  });

  final int indice;
  final PasoPropuesto paso;
  final VoidCallback onEditar;
  final void Function(Horizonte h) onHorizonte;
  final VoidCallback onQuitar;

  Color _color(Horizonte h) => switch (h) {
        Horizonte.ahora => MatixColors.red,
        Horizonte.pronto => MatixColors.amber,
        Horizonte.masAdelante => MatixColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: indice,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle,
                      color: MatixColors.muted, size: 20),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onEditar,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      paso.titulo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MatixColors.text,
                      ),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<Horizonte>(
                tooltip: 'Horizonte',
                onSelected: onHorizonte,
                itemBuilder: (_) => [
                  for (final h in Horizonte.values)
                    PopupMenuItem(value: h, child: Text(h.label)),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _color(paso.horizonte).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    paso.horizonte.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _color(paso.horizonte),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, color: MatixColors.muted),
                onPressed: onQuitar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

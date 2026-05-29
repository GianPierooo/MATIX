import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../application/plan_dia_controller.dart';
import '../domain/planificador.dart';

/// "Planifica mi día" (Urgencia-3): muestra la propuesta de bloques para
/// revisar (ajustar duración / quitar) y aceptar. Nada se agenda sin
/// confirmar. Es honesto: si no entra todo, lo dice.
class PlanificarDiaScreen extends ConsumerStatefulWidget {
  const PlanificarDiaScreen({super.key});

  @override
  ConsumerState<PlanificarDiaScreen> createState() =>
      _PlanificarDiaScreenState();
}

class _PlanificarDiaScreenState extends ConsumerState<PlanificarDiaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = ref.read(planDiaControllerProvider.notifier)
        ..reiniciar();
      ctrl.planificar();
    });
  }

  String _hhmm(DateTime d) => DateFormat.Hm().format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(planDiaControllerProvider);
    final ctrl = ref.read(planDiaControllerProvider.notifier);

    ref.listen<EstadoPlan>(planDiaControllerProvider, (prev, next) {
      if (prev?.fase == next.fase) return;
      if (next.fase == FasePlan.aplicado) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Listo: ${next.aplicados} '
                '${next.aplicados == 1 ? "bloque agendado" : "bloques agendados"}.'),
          ),
        );
        Navigator.of(context).pop();
      } else if (next.fase == FasePlan.revision && next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Planificar mi día')),
      body: switch (estado.fase) {
        FasePlan.inicial ||
        FasePlan.planificando =>
          const _Cargando(),
        FasePlan.error => _ErrorVista(
            mensaje: estado.error ?? 'Algo falló.',
            onReintentar: ctrl.planificar,
          ),
        _ => _Revision(
            plan: estado.plan!,
            aplicando: estado.fase == FasePlan.aplicando,
            hhmm: _hhmm,
            onQuitar: ctrl.quitar,
            onDuracion: (id, min) => ctrl.ajustarDuracion(id, min),
            onAceptar: ctrl.aplicar,
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
          Text('Armando tu día…',
              style: TextStyle(color: MatixColors.muted, fontSize: 13)),
        ],
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
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Revision extends StatelessWidget {
  const _Revision({
    required this.plan,
    required this.aplicando,
    required this.hhmm,
    required this.onQuitar,
    required this.onDuracion,
    required this.onAceptar,
  });

  final ResultadoPlan plan;
  final bool aplicando;
  final String Function(DateTime) hhmm;
  final void Function(String tareaId) onQuitar;
  final void Function(String tareaId, int minutos) onDuracion;
  final VoidCallback onAceptar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Nota honesta sobre cómo quedó el día.
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(MatixSpacing.l),
          decoration: BoxDecoration(
            color: plan.sinEspacio.isEmpty
                ? MatixColors.green.withValues(alpha: 0.12)
                : MatixColors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            plan.nota,
            style: const TextStyle(fontSize: 13, color: MatixColors.text),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
            children: [
              for (final b in plan.bloques)
                _BloqueTile(
                  bloque: b,
                  hhmm: hhmm,
                  onQuitar: () => onQuitar(b.tareaId),
                  onDuracion: (min) => onDuracion(b.tareaId, min),
                ),
              if (plan.sinEspacio.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 16, 16, 6),
                  child: Text(
                    'NO ENTRA HOY',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: MatixColors.muted,
                    ),
                  ),
                ),
                for (final s in plan.sinEspacio)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.bedtime_outlined,
                        color: MatixColors.muted, size: 18),
                    title: Text(s.titulo,
                        style: const TextStyle(
                            fontSize: 14, color: MatixColors.text)),
                    subtitle: Text(s.motivo,
                        style: const TextStyle(
                            fontSize: 12, color: MatixColors.muted)),
                  ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FilledButton.icon(
              onPressed:
                  (aplicando || plan.bloques.isEmpty) ? null : onAceptar,
              icon: aplicando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(plan.bloques.isEmpty
                  ? 'Nada que agendar'
                  : 'Aceptar ${plan.bloques.length} '
                      '${plan.bloques.length == 1 ? "bloque" : "bloques"}'),
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

class _BloqueTile extends StatelessWidget {
  const _BloqueTile({
    required this.bloque,
    required this.hhmm,
    required this.onQuitar,
    required this.onDuracion,
  });
  final BloquePropuesto bloque;
  final String Function(DateTime) hhmm;
  final VoidCallback onQuitar;
  final void Function(int minutos) onDuracion;

  @override
  Widget build(BuildContext context) {
    final mins = bloque.duracion.inMinutes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                '${hhmm(bloque.inicio)}–${hhmm(bloque.fin)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MatixColors.accent,
                ),
              ),
            ),
            Expanded(
              child: Text(
                bloque.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MatixColors.text,
                ),
              ),
            ),
            // Ajustar duración: menú con tamaños de bloque.
            PopupMenuButton<int>(
              tooltip: 'Duración',
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${mins}m',
                      style: const TextStyle(
                          fontSize: 12, color: MatixColors.muted)),
                  const Icon(Icons.arrow_drop_down,
                      color: MatixColors.muted, size: 18),
                ],
              ),
              onSelected: onDuracion,
              itemBuilder: (_) => [
                for (final m in const [15, 30, 45, 60, 90, 120])
                  PopupMenuItem(value: m, child: Text('$m min')),
              ],
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../domain/proyecto.dart';
import '../providers/proyectos_providers.dart';
import 'detalle_proyecto_screen.dart';
import 'nuevo_proyecto_screen.dart';
import 'widgets/barra_avance.dart';

class ProyectosListScreen extends ConsumerWidget {
  const ProyectosListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(proyectosListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proyectos'),
        actions: [
          IconButton(
            tooltip: 'Nuevo proyecto',
            onPressed: () => _abrirNuevo(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: lista.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => _Error(
          mensaje: e is MatixApiException ? e.message : e.toString(),
          onRetry: () => ref.invalidate(proyectosListProvider),
        ),
        data: (proyectos) {
          final activos = proyectos
              .where((p) => p.estado == EstadoProyecto.activo)
              .toList()
            ..sort((a, b) => (a.prioridad ?? 99).compareTo(b.prioridad ?? 99));
          final aparcados = proyectos
              .where((p) => p.estado == EstadoProyecto.aparcado)
              .toList();
          final terminados = proyectos
              .where((p) => p.estado == EstadoProyecto.terminado)
              .toList();
          return RefreshIndicator(
            color: MatixColors.accent,
            onRefresh: () async => ref.invalidate(proyectosListProvider),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                0,
                8,
                0,
                MatixLayout.bottomNavGuard(context),
              ),
              children: [
                _Seccion('Activos', '${activos.length} / 3'),
                if (activos.isEmpty)
                  const _Vacio('Aún no has activado ningún proyecto.'),
                ...activos.map((p) => _ActivoCard(proyecto: p)),
                if (aparcados.isNotEmpty) ...[
                  _Seccion('Aparcados', '${aparcados.length}',
                      right: 'En pausa consciente'),
                  ...aparcados.map((p) => _CompactCard(proyecto: p)),
                ],
                if (terminados.isNotEmpty) ...[
                  _Seccion('Terminados', '${terminados.length}'),
                  ...terminados.map((p) => _CompactCard(proyecto: p)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _abrirNuevo(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NuevoProyectoScreen()),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.label, this.count, {this.right});
  final String label;
  final String count;
  final String? right;
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
          const SizedBox(width: 8),
          Text(
            count,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MatixColors.muted,
            ),
          ),
          const Spacer(),
          if (right != null)
            Text(
              right!,
              style: const TextStyle(
                fontSize: 12,
                color: MatixColors.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio(this.msg);
  final String msg;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
      child: Text(
        msg,
        style: const TextStyle(fontSize: 13, color: MatixColors.muted),
      ),
    );
  }
}

Color _colorProyecto(Proyecto p) {
  if (p.color == null || p.color!.length != 7) return MatixColors.accent;
  final hex = p.color!.substring(1);
  final v = int.tryParse(hex, radix: 16);
  if (v == null) return MatixColors.accent;
  return Color(0xFF000000 | v);
}

class _ActivoCard extends StatelessWidget {
  const _ActivoCard({required this.proyecto});
  final Proyecto proyecto;

  @override
  Widget build(BuildContext context) {
    final color = _colorProyecto(proyecto);
    final calorColor = proyecto.enRiesgo ? MatixColors.red : MatixColors.green;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  DetalleProyectoScreen(proyectoId: proyecto.id),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        border: Border.all(color: color.withValues(alpha: 0.45)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '#${proyecto.prioridad ?? '-'}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        proyecto.nombre,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: MatixColors.text,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: calorColor.withValues(alpha: 0.14),
                        border: Border.all(
                            color: calorColor.withValues(alpha: 0.35)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        proyecto.enRiesgo
                            ? '${proyecto.etiquetaCalor} · RIESGO'
                            : proyecto.etiquetaCalor,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: calorColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (proyecto.avance != null) ...[
                  const SizedBox(height: 12),
                  BarraAvance(porcentaje: proyecto.avance!),
                ],
                if (proyecto.lineaMeta != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LÍNEA DE META',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: MatixColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          proyecto.lineaMeta!,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: MatixColors.text,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
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

class _CompactCard extends StatelessWidget {
  const _CompactCard({required this.proyecto});
  final Proyecto proyecto;

  @override
  Widget build(BuildContext context) {
    final color = _colorProyecto(proyecto);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  DetalleProyectoScreen(proyectoId: proyecto.id),
            ),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    proyecto.nombre,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: proyecto.estado == EstadoProyecto.terminado
                          ? MatixColors.muted
                          : MatixColors.text,
                      decoration: proyecto.estado == EstadoProyecto.terminado
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
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

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onRetry});
  final String mensaje;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: MatixColors.red, size: 40),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

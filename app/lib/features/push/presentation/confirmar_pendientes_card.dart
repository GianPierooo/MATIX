import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hub_refresh.dart';
import '../../../theme/matix_colors.dart';
import '../application/confirmacion_service.dart';
import '../domain/pendientes_confirmacion.dart';
import '../providers/pendientes_providers.dart';

/// Sección IN-APP "Pendientes de confirmar".
///
/// El problema que resuelve: en MagicOS/Honor las notis se entregan tarde o
/// nunca, y los botones de acción a veces no disparan. Con esto, el seguimiento
/// que el motor de evolución necesita ("¿lo hiciste? ¿fuiste?") vive TAMBIÉN en
/// la app — un toque y listo, sin esperar la noti.
///
/// Se muestra en Tu día (sobre los huecos libres) y en el Cierre del día. Lee
/// el endpoint determinista `/push/pendientes-confirmacion` (mismas tareas/
/// eventos que el motor de notis), y al confirmar llama exactamente los mismos
/// endpoints que la noti (`/rendicion-cuentas/accion`, `/asistencia/accion`).
/// Esto alimenta el motor de evolución igual.
class ConfirmarPendientesCard extends ConsumerStatefulWidget {
  const ConfirmarPendientesCard({super.key, this.compact = false});

  /// `true` para una variante compacta (cabe en la lista de Inicio/Tu día).
  /// `false` para la pantalla de cierre del día (más respiración).
  final bool compact;

  @override
  ConsumerState<ConfirmarPendientesCard> createState() =>
      _ConfirmarPendientesCardState();
}

class _ConfirmarPendientesCardState
    extends ConsumerState<ConfirmarPendientesCard> {
  // Las que el usuario YA tocó en esta vista (update optimista). Las ocultamos
  // al instante; el invalidarHub trae la verdad real del cerebro.
  final Set<String> _resueltas = {};
  bool _trabajando = false;

  Future<void> _confirmarTarea(TareaPendiente t, String accion) async {
    if (_trabajando) return;
    setState(() {
      _resueltas.add('t:${t.id}');
      _trabajando = true;
    });
    final svc = ref.read(confirmacionServiceProvider);
    final r = await svc.confirmarTarea(tareaId: t.id, accion: accion);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _resueltas.remove('t:${t.id}'));
      _aviso('No pude confirmar: ${r.mensaje ?? "error"}');
    } else {
      invalidarHub(ref); // refresca la fuente de verdad
      _aviso(_mensajeOk(accion));
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Future<void> _confirmarEvento(EventoPendiente e, String accion) async {
    if (_trabajando) return;
    setState(() {
      _resueltas.add('e:${e.id}');
      _trabajando = true;
    });
    final svc = ref.read(confirmacionServiceProvider);
    final r = await svc.confirmarAsistencia(eventoId: e.id, accion: accion);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _resueltas.remove('e:${e.id}'));
      _aviso('No pude confirmar: ${r.mensaje ?? "error"}');
    } else {
      invalidarHub(ref);
      _aviso(_mensajeOk(accion));
    }
    if (mounted) setState(() => _trabajando = false);
  }

  String _mensajeOk(String accion) => switch (accion) {
        'hecho' => 'Anotado: lo hiciste. Bien ahí.',
        'manana' => 'Listo, lo movemos a mañana.',
        'mas_tarde' => 'Listo, lo aplazo a más tarde hoy.',
        'si_fui' => 'Anotado: sí fuiste.',
        'no_fui' => 'Anotado: no fuiste.',
        'reprogramar' => 'Lo dejo para que lo reagendes.',
        _ => 'Listo.',
      };

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(pendientesConfirmacionProvider);
    final p = async.valueOrNull;
    if (p == null) {
      // Mientras carga (o si falla), no ocupamos espacio.
      return const SizedBox.shrink();
    }
    final tareas = p.tareas
        .where((t) => !_resueltas.contains('t:${t.id}'))
        .toList();
    final eventos = p.eventos
        .where((e) => !_resueltas.contains('e:${e.id}'))
        .toList();
    if (tareas.isEmpty && eventos.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MatixColors.amber.withValues(alpha: 0.35)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rtl,
                    size: 16, color: MatixColors.amber),
                const SizedBox(width: 8),
                const Text(
                  'PENDIENTES DE CONFIRMAR',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: MatixColors.muted,
                  ),
                ),
                const Spacer(),
                Text(
                  '${tareas.length + eventos.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MatixColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.compact
                  ? 'Cierra el círculo: confirma lo que ya pasó.'
                  : 'Confirma lo que hiciste y lo que no, para que el día '
                      'quede cerrado y Matix aprenda tu ritmo real.',
              style: const TextStyle(
                fontSize: 12, color: MatixColors.muted, height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            for (final t in tareas)
              _Fila(
                titulo: '«${t.titulo}»',
                contexto: '¿La hiciste? · ${humanoDesde(t.vencioHaceMin)}',
                botones: [
                  ('Sí', 'hecho', true),
                  ('No, más tarde', 'mas_tarde', false),
                  ('No, mañana', 'manana', false),
                ],
                habilitado: !_trabajando,
                onTap: (a) => _confirmarTarea(t, a),
              ),
            for (final e in eventos)
              _Fila(
                titulo: '¿Fuiste a «${e.titulo}»?',
                contexto: '${e.ubicacion ?? 'fuera de casa'} · '
                    'terminó ${humanoDesde(e.terminoHaceMin)}',
                botones: [
                  ('Sí fui', 'si_fui', true),
                  ('No fui', 'no_fui', false),
                  ('Reprogramar', 'reprogramar', false),
                ],
                habilitado: !_trabajando,
                onTap: (a) => _confirmarEvento(e, a),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.titulo,
    required this.contexto,
    required this.botones,
    required this.habilitado,
    required this.onTap,
  });
  final String titulo;
  final String contexto;
  // (label, actionId, primario)
  final List<(String, String, bool)> botones;
  final bool habilitado;
  final void Function(String accionId) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: MatixColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            contexto,
            style: const TextStyle(
              fontSize: 11.5, color: MatixColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (label, accion, primario) in botones)
                _Chip(
                  texto: label,
                  primario: primario,
                  enabled: habilitado,
                  onTap: () => onTap(accion),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.texto,
    required this.primario,
    required this.enabled,
    required this.onTap,
  });
  final String texto;
  final bool primario;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primario
          ? MatixColors.accent
          : MatixColors.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: primario ? Colors.white : MatixColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

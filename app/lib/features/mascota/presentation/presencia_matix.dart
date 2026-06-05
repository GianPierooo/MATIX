import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../horario/providers/horario_providers.dart';
import '../../matix/providers/matix_chat_providers.dart';
import '../../matix/providers/navegacion_matix_provider.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../domain/personalidad.dart';
import '../domain/presencia.dart';
import '../providers/mascota_providers.dart';
import 'avatar_matix.dart';

/// La presencia flotante de Matix: un robot vivo abajo en Inicio con una burbuja
/// que SIEMPRE muestra lo más relevante del momento (lee el plan del día + el
/// contexto + el reloj y se actualiza sola). Ambiental, no interrumpe; los pings
/// reales los dosifica la proactividad. Tocable: hacer / saltar / hablar / ver
/// el día. Minimizable. Si la mascota está apagada en Ajustes, no aparece.
class PresenciaMatix extends ConsumerStatefulWidget {
  const PresenciaMatix({super.key, required this.onVerMiDia});

  /// Lleva al usuario al bloque "TU DÍA" del Inicio.
  final VoidCallback onVerMiDia;

  @override
  ConsumerState<PresenciaMatix> createState() => _PresenciaMatixState();
}

class _PresenciaMatixState extends ConsumerState<PresenciaMatix> {
  Timer? _tick;
  Timer? _saludoTimer;
  Timer? _celebraTimer;
  bool _minimizado = false;
  bool _recienEntra = true;
  bool _celebrando = false;
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    // Se actualiza sola con el reloj (lo relevante cambia con la hora).
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
    // El saludo dura un ratito al entrar y luego cede a lo ambiental.
    _saludoTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _recienEntra = false);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _saludoTimer?.cancel();
    _celebraTimer?.cancel();
    super.dispose();
  }

  void _celebrar() {
    setState(() {
      _celebrando = true;
      _minimizado = false; // que se vea el brinco
    });
    _celebraTimer?.cancel();
    _celebraTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _celebrando = false);
    });
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _accion(AccionPresencia a, MensajePresencia m) async {
    switch (a) {
      case AccionPresencia.verMiDia:
        setState(() => _minimizado = false);
        widget.onVerMiDia();
      case AccionPresencia.hablemos:
        ref.read(objetivoNavegacionProvider.notifier).state =
            SeccionMatix.matix;
        await ref.read(chatMatixProvider.notifier).enviar(_seed(m.tipo));
      case AccionPresencia.seguimos:
        setState(() => _celebrando = false);
      case AccionPresencia.hecho:
        await _completar(m);
      case AccionPresencia.saltar:
        await _saltar(m);
    }
  }

  String _seed(TipoPresencia tipo) => switch (tipo) {
        TipoPresencia.ahora => '¿Cómo le entro a lo de ahora?',
        TipoPresencia.siguiente => '¿Qué me conviene preparar para lo que sigue?',
        TipoPresencia.libre => '¿Qué hago con este rato libre?',
        TipoPresencia.pendientes => '¿Por dónde retomo lo pendiente?',
        TipoPresencia.felicitacion => '¿Qué sigue?',
        TipoPresencia.saludo => 'Hola, ¿cómo vamos?',
        TipoPresencia.idle => 'Hola, ¿cómo vamos?',
      };

  Future<void> _completar(MensajePresencia m) async {
    if (m.tareaId == null && m.nodoId == null) {
      widget.onVerMiDia();
      return;
    }
    if (_trabajando) return;
    setState(() => _trabajando = true);
    try {
      await ref
          .read(horarioRepositoryProvider)
          .completar(tareaId: m.tareaId, nodoId: m.nodoId);
      ref.invalidate(planDiaProvider);
      ref.invalidate(tareasProvider);
      _aviso('Listo, lo marqué. Bien ahí.');
    } catch (e) {
      _aviso('No pude marcarlo: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _saltar(MensajePresencia m) async {
    if (m.setItemId == null) {
      setState(() => _minimizado = true);
      return;
    }
    if (_trabajando) return;
    setState(() => _trabajando = true);
    try {
      await ref.read(horarioRepositoryProvider).saltar(m.setItemId!);
      ref.invalidate(planDiaProvider);
      _aviso('Lo salté por hoy, sin culpa.');
    } catch (e) {
      _aviso('No pude saltarlo: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(mascotaConfigProvider);
    if (!cfg.habilitada) return const SizedBox.shrink();

    final ctx = ref.watch(contextoMascotaProvider);
    final plan = ref.watch(planDiaProvider).valueOrNull;

    // Celebra al detectar que cerraste algo (hechasHoy sube).
    ref.listen<ContextoMascota>(contextoMascotaProvider, (prev, next) {
      if (prev != null && next.hechasHoy > prev.hechasHoy) _celebrar();
    });

    final ahora = DateTime.now();
    final MensajePresencia msg;
    if (_celebrando) {
      msg = felicitacionPresencia(ctx, semilla: ahora.minute);
    } else if (_recienEntra) {
      final s = saludo(franjaDe(ahora.hour), ctx, semilla: ahora.day + ahora.hour);
      msg = MensajePresencia(
        tipo: TipoPresencia.saludo,
        texto: s.texto,
        acciones: const [AccionPresencia.hablemos, AccionPresencia.verMiDia],
      );
    } else {
      msg = mensajePresencia(plan, ctx, ahora);
    }

    final bottomGap = MediaQuery.viewPaddingOf(context).bottom + 86;

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 12, right: 12, bottom: bottomGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_minimizado)
              _Burbuja(
                msg: msg,
                trabajando: _trabajando,
                onAccion: (a) => _accion(a, msg),
                onMinimizar: () => setState(() => _minimizado = true),
              ),
            const SizedBox(height: 6),
            // El robot: tocarlo expande/colapsa la burbuja.
            GestureDetector(
              onTap: () => setState(() => _minimizado = !_minimizado),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MatixColors.accent.withValues(alpha: 0.30),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: AvatarMatix(size: 52, celebrando: _celebrando),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({
    required this.msg,
    required this.trabajando,
    required this.onAccion,
    required this.onMinimizar,
  });

  final MensajePresencia msg;
  final bool trabajando;
  final void Function(AccionPresencia) onAccion;
  final VoidCallback onMinimizar;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(sizeFactor: anim, axisAlignment: -1, child: child),
      ),
      child: Container(
        key: ValueKey(msg.texto),
        constraints: BoxConstraints(maxWidth: ancho * 0.82),
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
        decoration: BoxDecoration(
          color: MatixColors.cardHi,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MatixColors.accent.withValues(alpha: 0.35)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    msg.texto,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: MatixColors.text,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onMinimizar,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4, top: 1),
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 18, color: MatixColors.muted),
                  ),
                ),
              ],
            ),
            if (msg.acciones.isNotEmpty) ...[
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < msg.acciones.length; i++)
                      _Chip(
                        texto: msg.acciones[i].etiqueta,
                        primario: i == 0,
                        enabled: !trabajando,
                        onTap: () => onAccion(msg.acciones[i]),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hub_refresh.dart';
import '../../../core/markdown_plano.dart';
import '../../../theme/matix_colors.dart';
import '../../apuntes/providers/apuntes_providers.dart';
import '../../horario/providers/horario_providers.dart';
import '../../matix/presentation/manos_libres_screen.dart';
import '../../matix/providers/captura_apunte_providers.dart';
import '../../matix/providers/matix_chat_providers.dart';
import '../../matix/providers/navegacion_matix_provider.dart';
import '../../rollover/domain/rollover.dart';
import '../../rollover/providers/rollover_providers.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../domain/dosificacion.dart';
import '../domain/personalidad.dart';
import '../domain/presencia.dart';
import '../providers/mascota_providers.dart';
import 'avatar_matix.dart';

/// La presencia flotante de Matix: un robot-compañero vivo abajo en Inicio.
///
/// - Colapsado: solo el robot (flota, parpadea). Tocarlo reabre el mensaje.
/// - Expandido: robot + burbuja con el mensaje del momento + acciones tocables,
///   más una barra para anotar, dictar o ir al chat.
///
/// La burbuja ROTA sola entre mensajes según el plan, el contexto y la hora
/// (saludo, qué toca, qué sigue, rato libre, atrasos, aliento, dato, celebración)
/// para sentirse vivo sin repetir. Es ambiental: no interrumpe; los pings reales
/// los dosifica la proactividad. Respeta el silencio (22:00–08:00) bajando a un
/// mensaje tranquilo y sin rotar. Si la mascota está apagada en Ajustes, no
/// aparece.
class PresenciaMatix extends ConsumerStatefulWidget {
  const PresenciaMatix({super.key, required this.onVerMiDia});

  /// Lleva al usuario al bloque "TU DÍA" del Inicio.
  final VoidCallback onVerMiDia;

  @override
  ConsumerState<PresenciaMatix> createState() => _PresenciaMatixState();
}

class _PresenciaMatixState extends ConsumerState<PresenciaMatix> {
  Timer? _tick;
  Timer? _rota;
  Timer? _saludoTimer;
  Timer? _celebraTimer;
  bool _minimizado = false;
  bool _recienEntra = true;
  bool _celebrando = false;
  bool _trabajando = false;
  int _rotacion = 0;

  @override
  void initState() {
    super.initState();
    // Se actualiza con el reloj (lo relevante cambia con la hora).
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
    // Rota el mensaje ambiental cada ~40 s para que la burbuja "cambie sola".
    _rota = Timer.periodic(const Duration(seconds: 40), (_) {
      if (mounted) setState(() => _rotacion++);
    });
    // El saludo dura un ratito al entrar y luego cede a lo ambiental.
    _saludoTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _recienEntra = false);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rota?.cancel();
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
        await _irAlChat(_seed(m.tipo));
      case AccionPresencia.hecho:
        await _completar(m);
      case AccionPresencia.posponer:
        await _irAlChat('Pospón lo de ahora un rato y reacomoda mi día, porfa.');
      case AccionPresencia.saltar:
        await _saltar(m);
      case AccionPresencia.reprogramar:
        await _irAlChat(
            'Reprograma lo que se me pasó de fecha; muévelo a hoy si se puede.');
      case AccionPresencia.aceptarRollover:
        await _decidirRollover(m.tareaId, DecisionRollover.aceptar);
      case AccionPresencia.otroDia:
        await _decidirRollover(m.tareaId, DecisionRollover.otroDia);
      case AccionPresencia.soltar:
        await _decidirRollover(m.tareaId, DecisionRollover.soltar);
      case AccionPresencia.seguimos:
        setState(() => _celebrando = false);
    }
  }

  String _seed(TipoPresencia tipo) => switch (tipo) {
        TipoPresencia.ahora => '¿Cómo le entro a lo de ahora?',
        TipoPresencia.siguiente => '¿Qué me conviene preparar para lo que sigue?',
        TipoPresencia.libre => '¿Qué hago con este rato libre?',
        TipoPresencia.pendientes => '¿Por dónde retomo lo pendiente?',
        TipoPresencia.felicitacion => '¿Qué sigue?',
        TipoPresencia.rollover => '¿Cómo reacomodo lo que quedó pendiente?',
        TipoPresencia.saludo => 'Hola, ¿cómo vamos?',
        TipoPresencia.idle => 'Hola, ¿cómo vamos?',
      };

  /// Aplica la decisión de rollover sobre la tarea no cumplida y refresca.
  Future<void> _decidirRollover(String? tareaId, DecisionRollover d) async {
    if (tareaId == null || _trabajando) return;
    setState(() => _trabajando = true);
    try {
      await ref.read(rolloverRepositoryProvider).decidir(tareaId, d);
      ref.invalidate(rolloverProvider);
      ref.invalidate(planDiaProvider);
      ref.invalidate(tareasProvider);
      _aviso(switch (d) {
        DecisionRollover.aceptar => 'Listo, lo reagendé.',
        DecisionRollover.otroDia => 'Lo moví a otro día.',
        DecisionRollover.soltar => 'Lo solté, sin culpa.',
      });
    } catch (e) {
      _aviso('No pude moverlo: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// Navega al chat de Matix y manda una semilla (reusa Capa 2: chat/voz).
  Future<void> _irAlChat(String seed) async {
    ref.read(objetivoNavegacionProvider.notifier).state = SeccionMatix.matix;
    await ref.read(chatMatixProvider.notifier).enviar(seed);
  }

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
      // Una tarea = UNA entidad: refrescamos Tareas + plan + rollover en bloque
      // (cerrar algo temprano abre huecos → el rollover se recomputa).
      invalidarHub(ref);
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
      invalidarHub(ref);
      _aviso('Lo salté por hoy, sin culpa.');
    } catch (e) {
      _aviso('No pude saltarlo: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// Captura rápida por escrito: reusa el mismo flujo clasificado que el resto
  /// del hub (Matix decide dónde guardarlo). No abre el chat.
  Future<void> _capturaRapida() async {
    final ctrl = TextEditingController();
    final texto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MatixColors.card,
        title: const Text('Captura rápida',
            style: TextStyle(color: MatixColors.text, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(color: MatixColors.text),
          textInputAction: TextInputAction.send,
          onSubmitted: (v) => Navigator.pop(ctx, v),
          decoration: const InputDecoration(
            hintText: 'Anota algo…',
            hintStyle: TextStyle(color: MatixColors.muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: MatixColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Guardar',
                style: TextStyle(color: MatixColors.accent)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (texto == null || texto.trim().isEmpty || !mounted) return;
    try {
      final apunte =
          await ref.read(capturaApunteRepoProvider).capturar(texto.trim());
      ref.invalidate(apuntesListProvider);
      _aviso(apunte.destinoLabel);
    } catch (e) {
      _aviso('No pude guardar: $e');
    }
  }

  /// Dictar: abre el modo manos libres (voz) de Matix.
  void _dictar() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManosLibresScreen()),
    );
  }

  /// Menú del robot (long-press): todas las acciones en un solo lugar. Si hay
  /// algo accionable ahora, ofrece hacer/posponer/saltar/reprogramar; siempre
  /// ofrece captura rápida, dictar y hablar con Matix.
  Future<void> _menu(MensajePresencia? accionable) async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MatixColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            if (accionable != null) ...[
              ListTile(
                leading: const Icon(Icons.check_circle_outline,
                    color: MatixColors.accent),
                title: const Text('Hacer ahora'),
                onTap: () => Navigator.pop(ctx, 'hacer'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.schedule, color: MatixColors.accent),
                title: const Text('Posponer un rato'),
                onTap: () => Navigator.pop(ctx, 'posponer'),
              ),
              ListTile(
                leading: const Icon(Icons.skip_next, color: MatixColors.accent),
                title: const Text('Saltar por hoy'),
                onTap: () => Navigator.pop(ctx, 'saltar'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.event_repeat, color: MatixColors.accent),
                title: const Text('Reprogramar'),
                onTap: () => Navigator.pop(ctx, 'reprogramar'),
              ),
              const Divider(color: MatixColors.hairline, height: 8),
            ],
            ListTile(
              leading: const Icon(Icons.edit_note, color: MatixColors.accent),
              title: const Text('Captura rápida'),
              subtitle: const Text('Anota algo y yo lo guardo'),
              onTap: () => Navigator.pop(ctx, 'anotar'),
            ),
            ListTile(
              leading: const Icon(Icons.mic_none, color: MatixColors.accent),
              title: const Text('Dictar'),
              subtitle: const Text('Manos libres con Matix'),
              onTap: () => Navigator.pop(ctx, 'dictar'),
            ),
            ListTile(
              leading: const Icon(Icons.forum_outlined,
                  color: MatixColors.accent),
              title: const Text('Hablar con Matix'),
              onTap: () => Navigator.pop(ctx, 'hablar'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (opcion == null || !mounted) return;
    switch (opcion) {
      case 'hacer':
        if (accionable != null) await _completar(accionable);
      case 'posponer':
        await _irAlChat('Pospón lo de ahora un rato y reacomoda mi día, porfa.');
      case 'saltar':
        if (accionable != null) await _saltar(accionable);
      case 'reprogramar':
        await _irAlChat(
            'Reprograma lo que se me pasó de fecha; muévelo a hoy si se puede.');
      case 'anotar':
        await _capturaRapida();
      case 'dictar':
        _dictar();
      case 'hablar':
        await _irAlChat('Hola, ¿cómo vamos?');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(mascotaConfigProvider);
    if (!cfg.habilitada) return const SizedBox.shrink();

    final ctx = ref.watch(contextoMascotaProvider);
    final plan = ref.watch(planDiaProvider).valueOrNull;
    final rollover = ref.watch(rolloverProvider).valueOrNull;

    // Celebra al detectar que cerraste algo (hechasHoy sube).
    ref.listen<ContextoMascota>(contextoMascotaProvider, (prev, next) {
      if (prev != null && next.hechasHoy > prev.hechasHoy) _celebrar();
    });

    final ahora = DateTime.now();
    final silencio = enSilencio(ahora.hour, cfg.silencioInicio, cfg.silencioFin);

    final MensajePresencia msg;
    MensajePresencia? accionable;
    if (silencio) {
      // Respeta el silencio: un mensaje tranquilo, sin celebrar, rotar ni
      // surfacear rollovers.
      msg = const MensajePresencia(
        tipo: TipoPresencia.idle,
        texto: 'Modo noche. Acá ando bajito si me necesitas.',
        acciones: [AccionPresencia.hablemos, AccionPresencia.verMiDia],
      );
    } else if (_celebrando) {
      msg = felicitacionPresencia(ctx, semilla: ahora.minute);
    } else if (_recienEntra) {
      final s = saludo(franjaDe(ahora.hour), ctx, semilla: ahora.day + ahora.hour);
      msg = MensajePresencia(
        tipo: TipoPresencia.saludo,
        texto: s.texto,
        acciones: const [AccionPresencia.hablemos, AccionPresencia.verMiDia],
      );
      accionable = accionableActual(plan, ctx, ahora);
    } else if (rollover != null && rollover.sobrecarga.sobrecargado) {
      // Guardrail honesto: ya no es de mover de día, toca re-escopar/bajar carga.
      msg = MensajePresencia(
        tipo: TipoPresencia.rollover,
        texto: rollover.sobrecarga.mensaje ??
            'Estás arrastrando varias cosas. Bajemos la carga juntos.',
        acciones: const [AccionPresencia.hablemos, AccionPresencia.verMiDia],
      );
    } else if (rollover != null && rollover.proposals.isNotEmpty) {
      // Lo no cumplido NO muere callado: se propone moverlo, tocable.
      final p = rollover.proposals.first;
      final cuando = p.propuesta?.cuando;
      msg = MensajePresencia(
        tipo: TipoPresencia.rollover,
        texto: cuando != null && cuando.isNotEmpty
            ? 'Quedó «${p.titulo}» sin hacer. ¿Lo muevo a $cuando?'
            : 'Quedó «${p.titulo}» sin hacer. ¿Lo reacomodamos?',
        acciones: const [
          AccionPresencia.aceptarRollover,
          AccionPresencia.otroDia,
          AccionPresencia.soltar,
        ],
        tareaId: p.tareaId,
      );
    } else {
      msg = mensajePresencia(plan, ctx, ahora, rotacion: _rotacion);
      accionable = accionableActual(plan, ctx, ahora);
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
                onAnotar: _capturaRapida,
                onDictar: _dictar,
                onHablar: () => _irAlChat('Hola, ¿cómo vamos?'),
              ),
            const SizedBox(height: 6),
            // El robot: tocar = expandir/colapsar (restaurar); mantener = menú.
            _RobotFlotante(
              celebrando: _celebrando,
              minimizado: _minimizado,
              onTap: () => setState(() => _minimizado = !_minimizado),
              onLongPress: () => _menu(accionable),
            ),
          ],
        ),
      ),
    );
  }
}

/// El robot colapsable. Cuando está minimizado lleva un puntito de aviso para
/// señalar que es tocable (reabre el mensaje). Mantener presionado abre el menú.
class _RobotFlotante extends StatelessWidget {
  const _RobotFlotante({
    required this.celebrando,
    required this.minimizado,
    required this.onTap,
    required this.onLongPress,
  });

  final bool celebrando;
  final bool minimizado;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarMatix(size: 52, celebrando: celebrando),
            // Puntito "tócame para reabrir" cuando está colapsado.
            if (minimizado)
              Positioned(
                top: -1,
                right: -1,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: MatixColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: MatixColors.bg, width: 2),
                  ),
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
    required this.onAnotar,
    required this.onDictar,
    required this.onHablar,
  });

  final MensajePresencia msg;
  final bool trabajando;
  final void Function(AccionPresencia) onAccion;
  final VoidCallback onMinimizar;
  final VoidCallback onAnotar;
  final VoidCallback onDictar;
  final VoidCallback onHablar;

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
                    limpiarMarkdown(msg.texto),
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
            // Barra fija: captura rápida (escribir/dictar) y atajo al chat.
            const SizedBox(height: 8),
            const Divider(height: 1, color: MatixColors.hairline),
            const SizedBox(height: 4),
            Row(
              children: [
                _MiniAccion(
                    icono: Icons.edit_note, etiqueta: 'Anotar', onTap: onAnotar),
                _MiniAccion(
                    icono: Icons.mic_none, etiqueta: 'Dictar', onTap: onDictar),
                _MiniAccion(
                    icono: Icons.forum_outlined,
                    etiqueta: 'Hablar',
                    onTap: onHablar),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAccion extends StatelessWidget {
  const _MiniAccion({
    required this.icono,
    required this.etiqueta,
    required this.onTap,
  });
  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 16, color: MatixColors.accent),
            const SizedBox(width: 5),
            Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MatixColors.accent,
              ),
            ),
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

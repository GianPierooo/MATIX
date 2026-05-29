import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../matix/data/tts_service.dart';
import '../data/briefing_repository.dart';
import '../providers/briefing_providers.dart';

/// Pantalla que pinta el briefing matutino. Capa 8 reducida · Paso 1.
///
/// Se abre desde:
/// - Tocar la notificación de las 8 AM (deep link en `main.dart`).
/// - Acción "Ver briefing de hoy" en Ajustes.
///
/// La pantalla pide el briefing al cerebro al entrar y pinta las
/// secciones que tengan contenido. Un botón flotante reproduce el
/// `texto_para_voz` con el TTS de Matix (la misma voz onyx de OpenAI
/// del Capa 2 — Paso 4).
class BriefingScreen extends ConsumerStatefulWidget {
  const BriefingScreen({super.key});

  @override
  ConsumerState<BriefingScreen> createState() => _BriefingScreenState();
}

class _BriefingScreenState extends ConsumerState<BriefingScreen> {
  TtsService? _tts;
  bool _hablando = false;

  TtsService get _ttsLazy => _tts ??= TtsService();

  @override
  void dispose() {
    _tts?.dispose();
    super.dispose();
  }

  Future<void> _escuchar(String texto) async {
    setState(() => _hablando = true);
    try {
      await _ttsLazy.hablar(texto);
    } finally {
      if (mounted) setState(() => _hablando = false);
    }
  }

  Future<void> _detener() async {
    await _tts?.detener();
    if (mounted) setState(() => _hablando = false);
  }

  @override
  Widget build(BuildContext context) {
    final briefing = ref.watch(briefingHoyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Briefing de hoy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(briefingHoyProvider),
          ),
        ],
      ),
      body: briefing.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => _ErrorBody(
          mensaje: e.toString(),
          onReintentar: () => ref.invalidate(briefingHoyProvider),
        ),
        data: (b) => _BriefingBody(briefing: b),
      ),
      floatingActionButton: briefing.maybeWhen(
        data: (b) => FloatingActionButton.extended(
          backgroundColor: MatixColors.accent,
          foregroundColor: Colors.white,
          icon: Icon(_hablando ? Icons.stop : Icons.volume_up),
          label: Text(_hablando ? 'Detener' : 'Escuchar'),
          onPressed: _hablando ? _detener : () => _escuchar(b.textoParaVoz),
        ),
        orElse: () => null,
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.mensaje, required this.onReintentar});
  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: MatixColors.amber, size: 48),
          const SizedBox(height: 12),
          const Text(
            'No pude traer el briefing',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MatixColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: MatixColors.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
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
    );
  }
}

class _BriefingBody extends StatelessWidget {
  const _BriefingBody({required this.briefing});
  final BriefingHoy briefing;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _Header(briefing: briefing),
        const SizedBox(height: 12),
        if (briefing.eventos.isNotEmpty) ...[
          _Tarjeta(
            icono: Icons.event_outlined,
            titulo: 'Eventos',
            child: Column(
              children: [
                for (final ev in briefing.eventos) _EventoFila(ev: ev),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (briefing.tareasHoy.isNotEmpty) ...[
          _Tarjeta(
            icono: Icons.check_box_outline_blank,
            titulo: 'Tareas de hoy',
            child: Column(
              children: [
                for (final t in briefing.tareasHoy) _TareaFila(t: t),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (briefing.tareasVencidasTotal > 0) ...[
          _Tarjeta(
            icono: Icons.warning_amber_outlined,
            titulo: 'Vencidas',
            child: Text(
              briefing.tareasVencidasTotal == 1
                  ? 'Tenés 1 tarea vencida (hace ${briefing.tareasVencidasMasAntiguaDias} días).'
                  : 'Tenés ${briefing.tareasVencidasTotal} tareas vencidas. '
                      'La más antigua es de hace '
                      '${briefing.tareasVencidasMasAntiguaDias} días.',
              style: const TextStyle(
                fontSize: 13.5,
                color: MatixColors.text,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (briefing.alertas.isNotEmpty) ...[
          _Tarjeta(
            icono: Icons.error_outline,
            titulo: 'Alertas',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final a in briefing.alertas) _AlertaFila(a: a),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (briefing.eventos.isEmpty &&
            briefing.tareasHoy.isEmpty &&
            briefing.alertas.isEmpty &&
            briefing.tareasVencidasTotal == 0)
          const _DiaLibre(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.briefing});
  final BriefingHoy briefing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            briefing.saludo,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: MatixColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${briefing.diaSemana[0].toUpperCase()}${briefing.diaSemana.substring(1)} · ${briefing.resumenCorto}',
            style: const TextStyle(
              fontSize: 13,
              color: MatixColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.icono,
    required this.titulo,
    required this.child,
  });
  final IconData icono;
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: MatixColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: MatixColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _EventoFila extends StatelessWidget {
  const _EventoFila({required this.ev});
  final EventoBriefing ev;

  @override
  Widget build(BuildContext context) {
    final hora = ev.todoElDia
        ? 'Todo el día'
        : (ev.horaFin.isEmpty ? ev.hora : '${ev.hora}–${ev.horaFin}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              hora,
              style: const TextStyle(
                fontSize: 12.5,
                color: MatixColors.muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ev.titulo,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: MatixColors.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (ev.esDeGoogle)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: MatixColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Google',
                          style: TextStyle(
                            fontSize: 10,
                            color: MatixColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (ev.ubicacion != null && ev.ubicacion!.isNotEmpty)
                  Text(
                    ev.ubicacion!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: MatixColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TareaFila extends StatelessWidget {
  const _TareaFila({required this.t});
  final TareaBriefing t;

  Color get _colorPrio => switch (t.prioridad) {
        'alta' => MatixColors.red,
        'baja' => MatixColors.muted,
        _ => MatixColors.amber,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _colorPrio,
              borderRadius: BorderRadius.circular(3),
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
                    fontSize: 13.5,
                    color: MatixColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (t.contexto != null && t.contexto!.isNotEmpty)
                  Text(
                    t.contexto!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: MatixColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertaFila extends StatelessWidget {
  const _AlertaFila({required this.a});
  final AlertaBriefing a;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 8),
            child: Icon(
              Icons.circle,
              size: 6,
              color: MatixColors.amber,
            ),
          ),
          Expanded(
            child: Text(
              a.mensaje,
              style: const TextStyle(
                fontSize: 13,
                color: MatixColors.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaLibre extends StatelessWidget {
  const _DiaLibre();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          Icon(Icons.wb_sunny_outlined, color: MatixColors.green, size: 36),
          SizedBox(height: 8),
          Text(
            'Tenés la agenda libre',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: MatixColors.text,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Nada que correr hoy. Aprovechá para avanzar lo que tengas pendiente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: MatixColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

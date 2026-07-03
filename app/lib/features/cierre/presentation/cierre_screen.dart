import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_button_styles.dart';
import '../../matix/data/tts_service.dart';
import '../data/cierre_repository.dart';
import '../providers/cierre_providers.dart';

/// Pantalla del cierre del día. Capa 8 · Paso 2.
///
/// Se abre desde:
/// - Tocar la notificación de las 21:00 (deep link en `main.dart`).
/// - Acción "Ver cierre de hoy" en Ajustes.
///
/// Tono de cierre: repaso amable, no lista de deberes. El FAB
/// reproduce el `texto_para_voz` con la misma voz onyx del briefing.
class CierreScreen extends ConsumerStatefulWidget {
  const CierreScreen({super.key});

  @override
  ConsumerState<CierreScreen> createState() => _CierreScreenState();
}

class _CierreScreenState extends ConsumerState<CierreScreen> {
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
    final cierre = ref.watch(cierreHoyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierre del día'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(cierreHoyProvider),
          ),
        ],
      ),
      body: cierre.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => _ErrorBody(
          mensaje: e.toString(),
          onReintentar: () => ref.invalidate(cierreHoyProvider),
        ),
        data: (c) => _CierreBody(cierre: c),
      ),
      floatingActionButton: cierre.maybeWhen(
        data: (c) => FloatingActionButton.extended(
          backgroundColor: MatixColors.accent,
          foregroundColor: Colors.white,
          icon: Icon(_hablando ? Icons.stop : Icons.volume_up),
          label: Text(_hablando ? 'Detener' : 'Escuchar'),
          onPressed: _hablando ? _detener : () => _escuchar(c.textoParaVoz),
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
            'No pude traer el cierre',
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
            style: MatixButtonStyles.primario,
          ),
        ],
      ),
    );
  }
}

class _CierreBody extends StatelessWidget {
  const _CierreBody({required this.cierre});
  final CierreHoy cierre;

  @override
  Widget build(BuildContext context) {
    final hayManana =
        cierre.tareasManana.isNotEmpty || cierre.eventosManana.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _Header(cierre: cierre),
        const SizedBox(height: 12),
        if (cierre.hechas.isNotEmpty) ...[
          _Tarjeta(
            icono: Icons.check_circle_outline,
            titulo: 'Lo que hiciste hoy',
            child: Column(
              children: [
                for (final h in cierre.hechas) _HechaFila(h: h),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (cierre.pendientesHoy.isNotEmpty) ...[
          _Tarjeta(
            icono: Icons.schedule,
            titulo: 'Quedó para después',
            child: Column(
              children: [
                for (final p in cierre.pendientesHoy) _PendienteFila(p: p),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (hayManana) ...[
          _Tarjeta(
            icono: Icons.wb_twilight,
            titulo: 'Mañana',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in cierre.eventosManana) _EventoMananaFila(e: e),
                for (final t in cierre.tareasManana) _PendienteFila(p: t),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        // La frase para soltar — siempre presente, cierra la pantalla.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MatixColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: MatixColors.accent.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1, right: 10),
                child: Icon(
                  Icons.nightlight_round,
                  color: MatixColors.accent,
                  size: 20,
                ),
              ),
              Expanded(
                child: Text(
                  cierre.cierreFrase,
                  style: const TextStyle(
                    fontSize: 14,
                    color: MatixColors.text,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.cierre});
  final CierreHoy cierre;

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
            cierre.saludo,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: MatixColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${cierre.diaSemana[0].toUpperCase()}${cierre.diaSemana.substring(1)} · ${cierre.resumenCorto}',
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

class _HechaFila extends StatelessWidget {
  const _HechaFila({required this.h});
  final TareaHecha h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 10),
            child: Icon(Icons.check, size: 16, color: MatixColors.green),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.titulo,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: MatixColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (h.contexto != null && h.contexto!.isNotEmpty)
                  Text(
                    h.contexto!,
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

class _PendienteFila extends StatelessWidget {
  const _PendienteFila({required this.p});
  final TareaPendiente p;

  Color get _colorPrio => switch (p.prioridad) {
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
            margin: const EdgeInsets.only(top: 6, right: 10),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _colorPrio,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.titulo,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: MatixColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (p.contexto != null && p.contexto!.isNotEmpty)
                  Text(
                    p.contexto!,
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

class _EventoMananaFila extends StatelessWidget {
  const _EventoMananaFila({required this.e});
  final EventoManana e;

  @override
  Widget build(BuildContext context) {
    final hora = e.todoElDia ? 'Todo el día' : e.hora;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
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
            child: Text(
              e.titulo,
              style: const TextStyle(
                fontSize: 13.5,
                color: MatixColors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

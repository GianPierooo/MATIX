import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../domain/mensaje.dart';
import '../providers/manos_libres_providers.dart';
import '../providers/matix_chat_providers.dart';
import 'widgets/texto_con_enlaces.dart';

/// Modo manos libres (Capa 2 Paso 5.1, rehecho).
///
/// La pantalla muestra:
/// - Header con "Salir".
/// - El **transcript completo** de la conversación (mismo historial
///   que el chat normal — `chatMatixProvider`). Es scrolleable y
///   tiene texto completo, sin recortar.
/// - Indicador grande de fase (escuchando / pensando / hablando /
///   en pausa) con su color y animación.
/// - Acciones inferiores: "Salir", "Pausar" cuando está activo,
///   "Hablar" cuando está en pausa.
///
/// Toda la lógica vive en `manosLibresProvider`. Esta pantalla solo
/// pinta y dispara acciones.
class ManosLibresScreen extends ConsumerStatefulWidget {
  const ManosLibresScreen({
    super.key,
    this.seedMensaje,
    this.porWakeWord = false,
  });

  /// Si no nulo, el modo arranca como si el usuario hubiera dicho
  /// este texto. Lo usan los botones de ritual de Inicio
  /// ("Buenos días" / "Cierre del día") para entrar al modo con
  /// la conversación ya disparada por el saludo correspondiente.
  final String? seedMensaje;

  /// `true` cuando se abrió porque el usuario dijo "oye matix". Matix saluda
  /// por voz ("Hola Piero!") y ofrece retomar si hay conversación reciente.
  final bool porWakeWord;

  @override
  ConsumerState<ManosLibresScreen> createState() =>
      _ManosLibresScreenState();
}

class _ManosLibresScreenState extends ConsumerState<ManosLibresScreen> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // El relevo de micro lo posee el notifier de manos libres (el que usa el
    // micrófono): `entrar()` enciende `modoVozActivoProvider` y `salir()` lo
    // suelta. `salir()` se llama desde deactivate() (abajo), que SIEMPRE corre
    // al cerrar — así el wake word reanuda con seguridad y nunca queda pegado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(manosLibresProvider.notifier);
      if (widget.porWakeWord) {
        notifier.entrarPorWakeWord();
      } else {
        notifier.entrar(seedMensaje: widget.seedMensaje);
      }
    });
  }

  @override
  void deactivate() {
    ref.read(manosLibresProvider.notifier).salir();
    super.deactivate();
  }

  @override
  void dispose() {
    // El reset del relevo de micro ya lo hizo `salir()` (desde deactivate()).
    // Aquí solo liberamos recursos de la pantalla.
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _salir() async {
    await ref.read(manosLibresProvider.notifier).salir();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(manosLibresProvider);
    final mensajes = ref.watch(
      chatMatixProvider.select((s) => s.mensajes),
    );

    // Si llegan mensajes nuevos, scrolleamos al final.
    ref.listen<List<Mensaje>>(
      chatMatixProvider.select((s) => s.mensajes),
      (_, _) => _scrollAlFinal(),
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(manosLibresProvider.notifier).salir();
        }
      },
      child: Scaffold(
        backgroundColor: MatixColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _Header(onSalir: _salir),
              // Transcript scrolleable arriba (más espacio).
              Expanded(
                flex: 5,
                child: mensajes.isEmpty
                    ? const _TranscriptVacio()
                    : _Transcript(
                        mensajes: mensajes,
                        scrollCtrl: _scrollCtrl,
                      ),
              ),
              // Indicador de estado, más chico que antes.
              _IndicadorFase(estado: estado),
              // Acciones.
              Padding(
                padding: const EdgeInsets.all(MatixSpacing.xl2),
                child: _Acciones(estado: estado),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────── Header ──────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onSalir});
  final VoidCallback onSalir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MatixSpacing.l,
        MatixSpacing.l,
        MatixSpacing.l,
        MatixSpacing.m,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Salir del modo manos libres',
            icon: const Icon(Icons.close, size: 28),
            onPressed: onSalir,
          ),
          const SizedBox(width: MatixSpacing.s),
          Text('Modo manos libres', style: MatixText.subtitle),
        ],
      ),
    );
  }
}

// ───────────────────── Transcript ──────────────────────────────────

class _TranscriptVacio extends StatelessWidget {
  const _TranscriptVacio();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MatixSpacing.xl2),
      child: Center(
        child: Text(
          'Háblale a Matix. La conversación aparecerá aquí.',
          textAlign: TextAlign.center,
          style: MatixText.small,
        ),
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.mensajes, required this.scrollCtrl});
  final List<Mensaje> mensajes;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(
        MatixSpacing.xl,
        MatixSpacing.m,
        MatixSpacing.xl,
        MatixSpacing.l,
      ),
      itemCount: mensajes.length,
      itemBuilder: (_, i) => _MensajeBurbuja(mensaje: mensajes[i]),
    );
  }
}

class _MensajeBurbuja extends StatelessWidget {
  const _MensajeBurbuja({required this.mensaje});
  final Mensaje mensaje;

  @override
  Widget build(BuildContext context) {
    final esUsuario = mensaje.rol == RolMensaje.usuario;
    final color = esUsuario ? MatixColors.accent : MatixColors.card;
    final colorTexto = esUsuario ? Colors.white : MatixColors.text;
    final etiqueta = esUsuario ? 'Tú' : 'Matix';
    final etiquetaColor =
        esUsuario ? Colors.white.withValues(alpha: 0.7) : MatixColors.purple;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MatixSpacing.s),
      child: Align(
        alignment:
            esUsuario ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MatixSpacing.xl,
              vertical: MatixSpacing.l,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
              border: esUsuario
                  ? null
                  : Border.all(color: MatixColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: MatixText.micro.copyWith(
                    color: etiquetaColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: MatixSpacing.s),
                TextoConEnlaces(
                  mensaje.contenido,
                  style: MatixText.body.copyWith(color: colorTexto),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────── Indicador de fase ───────────────────────────

class _IndicadorFase extends StatelessWidget {
  const _IndicadorFase({required this.estado});
  final EstadoManosLibres estado;

  @override
  Widget build(BuildContext context) {
    final (texto, sub) = switch (estado.fase) {
      FaseManosLibres.inactivo => ('—', ''),
      FaseManosLibres.iniciando => ('Preparando', 'Activando micrófono'),
      FaseManosLibres.escuchando => (
          'Escuchando',
          'Habla y dale a Enviar cuando termines',
        ),
      FaseManosLibres.transcribiendo => ('Transcribiendo', ''),
      FaseManosLibres.pensando => ('Pensando', ''),
      FaseManosLibres.hablando => ('Hablando', 'Matix te responde'),
      FaseManosLibres.enPausa => (
          'En pausa',
          estado.notaPausa ?? 'Toca "Hablar" para reanudar',
        ),
      FaseManosLibres.error => ('Error', estado.error ?? 'Algo salió mal'),
    };

    final color = switch (estado.fase) {
      FaseManosLibres.escuchando => MatixColors.green,
      FaseManosLibres.transcribiendo => MatixColors.accent,
      FaseManosLibres.pensando => MatixColors.amber,
      FaseManosLibres.hablando => MatixColors.purple,
      FaseManosLibres.enPausa => MatixColors.muted,
      FaseManosLibres.error => MatixColors.red,
      _ => MatixColors.muted,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MatixSpacing.xl,
        vertical: MatixSpacing.l,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: _Anillo(estado: estado, color: color),
          ),
          const SizedBox(width: MatixSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  texto,
                  style: MatixText.subtitle.copyWith(color: color),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: MatixSpacing.xs),
                  Text(sub, style: MatixText.small),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Anillo extends StatefulWidget {
  const _Anillo({required this.estado, required this.color});
  final EstadoManosLibres estado;
  final Color color;

  @override
  State<_Anillo> createState() => _AnilloState();
}

class _AnilloState extends State<_Anillo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // Período corto para que la onda se sienta viva con el habla.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final escuchando =
            widget.estado.fase == FaseManosLibres.escuchando;
        // La onda pulsa con la REPRODUCCIÓN real (no con la fase): mientras
        // Matix suena. Si está "hablando" pero todavía descargando el audio
        // (`reproduciendo=false`), el anillo queda quieto — sin desfase.
        final sonando = widget.estado.reproduciendo;

        final db = widget.estado.nivelDb;
        final norm = (((db + 60).clamp(0, 50)) / 50).toDouble();
        final t = _c.value * 2 * pi;
        // Onda orgánica (dos armónicos) para el habla; amplitud del mic para
        // la escucha; quieto en el resto.
        final onda = (0.5 + 0.5 * (0.7 * sin(t) + 0.3 * sin(t * 2.6)))
            .clamp(0.0, 1.0)
            .toDouble();
        final double intensidad = escuchando
            ? norm
            : sonando
                ? onda
                : 0.0;
        final pulso = 0.6 + 0.4 * intensidad;
        final activo = escuchando || sonando;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Halo que respira (la "luz"): solo cuando escucha o suena.
            if (activo)
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      widget.color.withValues(alpha: 0.08 + 0.12 * intensidad),
                ),
              ),
            // Círculo que pulsa con la onda.
            Container(
              width: 70 * pulso,
              height: 70 * pulso,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.16),
              ),
            ),
            if (widget.estado.fase == FaseManosLibres.transcribiendo ||
                widget.estado.fase == FaseManosLibres.pensando)
              SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(widget.color),
                ),
              ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
              child: Icon(
                _iconoDeFase(widget.estado.fase),
                size: 22,
                color: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _iconoDeFase(FaseManosLibres f) => switch (f) {
        FaseManosLibres.escuchando => Icons.mic,
        FaseManosLibres.transcribiendo => Icons.translate,
        FaseManosLibres.pensando => Icons.psychology_alt_outlined,
        FaseManosLibres.hablando => Icons.volume_up,
        FaseManosLibres.enPausa => Icons.pause,
        FaseManosLibres.error => Icons.error_outline,
        _ => Icons.auto_awesome,
      };
}

// ───────────────────── Acciones inferiores ─────────────────────────

class _Acciones extends ConsumerWidget {
  const _Acciones({required this.estado});
  final EstadoManosLibres estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (estado.fase == FaseManosLibres.error) {
      final permanente =
          estado.error?.contains('ajustes del sistema') ?? false;
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              label: const Text('Cerrar'),
            ),
          ),
          if (permanente) ...[
            const SizedBox(width: MatixSpacing.l),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Ajustes'),
              ),
            ),
          ],
        ],
      );
    }

    final notifier = ref.read(manosLibresProvider.notifier);
    final puedeStop = estado.fase == FaseManosLibres.hablando;
    final escuchando = estado.fase == FaseManosLibres.escuchando;
    final enPausa = estado.fase == FaseManosLibres.enPausa;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              await notifier.salir();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close),
            label: const Text('Salir'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: MatixSpacing.xl,
              ),
              foregroundColor: MatixColors.text,
              side: const BorderSide(color: MatixColors.hairline),
            ),
          ),
        ),
        const SizedBox(width: MatixSpacing.l),
        if (enPausa)
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: notifier.reanudar,
              icon: const Icon(Icons.mic),
              label: const Text('Hablar'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: MatixSpacing.xl,
                ),
                backgroundColor: MatixColors.green,
                foregroundColor: Colors.white,
              ),
            ),
          )
        else if (puedeStop)
          Expanded(
            child: FilledButton.icon(
              onPressed: notifier.interrumpirHabla,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Detener'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: MatixSpacing.xl,
                ),
                backgroundColor: MatixColors.purple,
                foregroundColor: Colors.white,
              ),
            ),
          )
        else if (escuchando)
          // Cortar la escucha y transcribir lo dicho hasta acá (como en
          // la captura de apuntes): no hay que esperar al silencio.
          Expanded(
            child: FilledButton.icon(
              onPressed: notifier.detenerYTranscribir,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: MatixSpacing.xl,
                ),
                backgroundColor: MatixColors.green,
                foregroundColor: Colors.white,
              ),
            ),
          )
        else
          Expanded(
            child: FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: MatixSpacing.xl,
                ),
                backgroundColor: MatixColors.cardHi,
                foregroundColor: MatixColors.text,
                disabledBackgroundColor: MatixColors.cardHi,
                disabledForegroundColor: MatixColors.muted,
              ),
            ),
          ),
      ],
    );
  }
}

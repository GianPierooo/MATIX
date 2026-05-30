import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../../apuntes/application/guardar_apunte_controller.dart';
import '../../apuntes/presentation/editor_apunte_screen.dart';
import '../application/extraccion_eventos_controller.dart';
import '../application/extraccion_recibo_controller.dart';
import '../application/extraccion_tareas_controller.dart';
import '../domain/destino_ocr.dart';
import 'captura_camara_screen.dart';
import 'revision_eventos_screen.dart';
import 'revision_recibo_screen.dart';
import 'revision_tareas_screen.dart';

export '../domain/destino_ocr.dart' show DestinoOcr;

/// Muestra el texto que extrajo el OCR en un campo **editable**, para
/// que el usuario corrija lo que ML Kit haya errado (Capa 7-A) y, con
/// el botón de acción, lo convierta según [destino]:
///
/// - [DestinoOcr.tareas]: "Convertir en tareas" → hoja de revisión (7-B).
/// - [DestinoOcr.apunte]: "Guardar como apunte" → apunte clasificado.
///
/// La edición vive acá como estado local del `TextEditingController`.
/// SOLO el texto (ya corregido) viaja al cerebro: la imagen se quedó
/// en el teléfono (7-A).
///
/// Si [aviso] viene con texto (OCR vacío, falló, o cámara no
/// disponible), pintamos un banner ámbar y el campo arranca vacío para
/// escribir a mano. Nunca se cierra en silencio.
class ResultadoOcrScreen extends ConsumerStatefulWidget {
  const ResultadoOcrScreen({
    super.key,
    required this.textoInicial,
    this.aviso,
    this.destino = DestinoOcr.tareas,
  });

  final String textoInicial;
  final String? aviso;
  final DestinoOcr destino;

  @override
  ConsumerState<ResultadoOcrScreen> createState() =>
      _ResultadoOcrScreenState();
}

class _ResultadoOcrScreenState extends ConsumerState<ResultadoOcrScreen> {
  late final TextEditingController _texto;

  /// El destino arranca con lo que sugirió la clasificación, pero es
  /// editable: el usuario corrige el tipo con el selector ("esto en
  /// realidad es → …") y se reabre el flujo correcto.
  late DestinoOcr _destino;

  @override
  void initState() {
    super.initState();
    _texto = TextEditingController(text: widget.textoInicial);
    _destino = widget.destino;
    // Arrancamos el flujo limpio: si quedó estado de una captura
    // anterior, lo reseteamos para que el `ref.listen` no dispare una
    // navegación fantasma al montar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reiniciarFlujo(_destino);
    });
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _reiniciarFlujo(DestinoOcr destino) {
    switch (destino) {
      case DestinoOcr.apunte:
        ref.read(guardarApunteControllerProvider.notifier).reiniciar();
      case DestinoOcr.eventos:
        ref.read(extraccionEventosControllerProvider.notifier).reiniciar();
      case DestinoOcr.tareas:
        ref.read(extraccionTareasControllerProvider.notifier).reiniciar();
      case DestinoOcr.recibo:
        ref.read(extraccionReciboControllerProvider.notifier).reiniciar();
    }
  }

  /// Corrige el tipo cuando Matix adivinó mal. El mismo texto ya
  /// corregido se reusa; solo cambia a qué flujo de revisión se manda.
  void _cambiarDestino(DestinoOcr nuevo) {
    if (nuevo == _destino) return;
    setState(() => _destino = nuevo);
    // Limpiamos el estado del flujo nuevo para que su `ref.listen` no
    // dispare una navegación con datos de una corrida anterior.
    _reiniciarFlujo(nuevo);
  }

  void _capturarOtra() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CapturaCamaraScreen()),
    );
  }

  void _accion() {
    switch (_destino) {
      case DestinoOcr.apunte:
        ref.read(guardarApunteControllerProvider.notifier).guardar(_texto.text);
      case DestinoOcr.eventos:
        ref
            .read(extraccionEventosControllerProvider.notifier)
            .interpretar(_texto.text);
      case DestinoOcr.tareas:
        ref
            .read(extraccionTareasControllerProvider.notifier)
            .interpretar(_texto.text);
      case DestinoOcr.recibo:
        ref
            .read(extraccionReciboControllerProvider.notifier)
            .interpretar(_texto.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_destino) {
      case DestinoOcr.apunte:
        _escucharApunte();
      case DestinoOcr.eventos:
        _escucharEventos();
      case DestinoOcr.tareas:
        _escucharTareas();
      case DestinoOcr.recibo:
        _escucharRecibo();
    }

    final ocupado = switch (_destino) {
      DestinoOcr.apunte => ref.watch(guardarApunteControllerProvider).fase ==
          FaseGuardarApunte.guardando,
      DestinoOcr.eventos =>
        ref.watch(extraccionEventosControllerProvider).fase ==
            FaseEventos.interpretando,
      DestinoOcr.tareas => ref.watch(extraccionTareasControllerProvider).fase ==
          FaseExtraccion.interpretando,
      DestinoOcr.recibo => ref.watch(extraccionReciboControllerProvider).fase ==
          FaseRecibo.interpretando,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Texto extraído'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MatixSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.aviso != null) ...[
                _AvisoBanner(mensaje: widget.aviso!),
                const SizedBox(height: MatixSpacing.l),
              ],
              _SelectorTipo(
                destino: _destino,
                onChanged: ocupado ? null : _cambiarDestino,
              ),
              const SizedBox(height: MatixSpacing.l),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(MatixSpacing.l),
                  decoration: BoxDecoration(
                    color: MatixColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MatixColors.hairline),
                  ),
                  child: TextField(
                    controller: _texto,
                    autofocus: widget.aviso != null,
                    maxLines: null,
                    minLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: MatixText.body.copyWith(height: 1.5),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'El texto extraído aparece aquí. Edítalo '
                          'para corregir lo que el OCR haya errado.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: MatixSpacing.l),
              FilledButton.icon(
                onPressed: ocupado ? null : _accion,
                icon: ocupado
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : Icon(_iconoBoton(), size: 18),
                label: Text(_etiquetaBoton(ocupado)),
                style: FilledButton.styleFrom(
                  backgroundColor: MatixColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: MatixSpacing.m),
              OutlinedButton.icon(
                onPressed: ocupado ? null : _capturarOtra,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Capturar otra'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MatixColors.text,
                  side: const BorderSide(color: MatixColors.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconoBoton() => switch (_destino) {
        DestinoOcr.apunte => Icons.note_add_outlined,
        DestinoOcr.eventos => Icons.event_outlined,
        DestinoOcr.tareas => Icons.checklist_outlined,
        DestinoOcr.recibo => Icons.receipt_long_outlined,
      };

  String _etiquetaBoton(bool ocupado) => switch (_destino) {
        DestinoOcr.apunte =>
          ocupado ? 'Guardando…' : 'Guardar como apunte',
        DestinoOcr.eventos =>
          ocupado ? 'Leyendo…' : 'Convertir en eventos',
        DestinoOcr.tareas =>
          ocupado ? 'Convirtiendo…' : 'Convertir en tareas',
        DestinoOcr.recibo =>
          ocupado ? 'Leyendo…' : 'Revisar gasto',
      };

  // ─── Camino tareas (Capa 7-B) ─────────────────────────────────────
  void _escucharTareas() {
    // Cuando el cerebro responde, saltamos a la hoja de revisión. Si
    // falla, mostramos el error y dejamos reintentar (el botón sigue).
    ref.listen<EstadoExtraccion>(extraccionTareasControllerProvider,
        (prev, next) {
      if (prev?.fase == next.fase) return;
      if (next.fase == FaseExtraccion.revision) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RevisionTareasScreen()),
        );
      } else if (next.fase == FaseExtraccion.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? 'No pude convertir el texto.'),
            action: SnackBarAction(label: 'Reintentar', onPressed: _accion),
          ),
        );
      }
    });
  }

  // ─── Camino eventos (sílabo → eventos) ────────────────────────────
  void _escucharEventos() {
    ref.listen<EstadoEventos>(extraccionEventosControllerProvider,
        (prev, next) {
      if (prev?.fase == next.fase) return;
      if (next.fase == FaseEventos.revision) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RevisionEventosScreen()),
        );
      } else if (next.fase == FaseEventos.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? 'No pude leer el sílabo.'),
            action: SnackBarAction(label: 'Reintentar', onPressed: _accion),
          ),
        );
      }
    });
  }

  // ─── Camino apunte (Paso C — clasificación) ───────────────────────
  void _escucharApunte() {
    ref.listen<EstadoGuardarApunte>(guardarApunteControllerProvider,
        (prev, next) {
      if (prev?.fase == next.fase) return;
      if (next.fase == FaseGuardarApunte.guardado && next.resultado != null) {
        final apunte = next.resultado!;
        // Confirmamos dónde quedó archivado y abrimos el editor para
        // afinar el apunte recién creado (reemplaza esta pantalla para
        // no dejar la captura en el back stack).
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apunte.destinoLabel)),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EditorApunteScreen(apunteId: apunte.id),
          ),
        );
      } else if (next.fase == FaseGuardarApunte.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? 'No pude guardar el apunte.'),
            action: SnackBarAction(label: 'Reintentar', onPressed: _accion),
          ),
        );
      }
    });
  }

  // ─── Camino recibo (Finanzas-2 → gasto) ───────────────────────────
  void _escucharRecibo() {
    ref.listen<EstadoRecibo>(extraccionReciboControllerProvider,
        (prev, next) {
      if (prev?.fase == next.fase) return;
      if (next.fase == FaseRecibo.revision) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RevisionReciboScreen()),
        );
      } else if (next.fase == FaseRecibo.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? 'No pude leer el recibo.'),
            action: SnackBarAction(label: 'Reintentar', onPressed: _accion),
          ),
        );
      }
    });
  }
}

/// Selector "esto en realidad es → tareas / eventos / apunte".
///
/// Arranca en lo que Matix clasificó; si adivinó mal, el usuario toca
/// el tipo correcto y la pantalla reabre el flujo adecuado con el mismo
/// texto. Se deshabilita mientras un flujo está trabajando.
class _SelectorTipo extends StatelessWidget {
  const _SelectorTipo({required this.destino, required this.onChanged});

  final DestinoOcr destino;
  final ValueChanged<DestinoOcr>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Matix detectó qué es. Si se equivocó, cámbialo:',
          style: MatixText.small.copyWith(color: MatixColors.muted),
        ),
        const SizedBox(height: MatixSpacing.m),
        SizedBox(
          width: double.infinity,
          // Cuatro tipos (tareas/eventos/apunte/recibo): sin iconos para
          // que entren cómodos a lo ancho del teléfono.
          child: SegmentedButton<DestinoOcr>(
            segments: const [
              ButtonSegment(value: DestinoOcr.tareas, label: Text('Tareas')),
              ButtonSegment(value: DestinoOcr.eventos, label: Text('Eventos')),
              ButtonSegment(value: DestinoOcr.apunte, label: Text('Apunte')),
              ButtonSegment(value: DestinoOcr.recibo, label: Text('Recibo')),
            ],
            selected: {destino},
            onSelectionChanged: onChanged == null
                ? null
                : (seleccion) => onChanged!(seleccion.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(MatixText.small),
            ),
          ),
        ),
      ],
    );
  }
}

class _AvisoBanner extends StatelessWidget {
  const _AvisoBanner({required this.mensaje});
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MatixSpacing.l),
      decoration: BoxDecoration(
        color: MatixColors.amber.withValues(alpha: 0.12),
        border: Border.all(color: MatixColors.amber.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: MatixColors.amber, size: 18),
          const SizedBox(width: MatixSpacing.m),
          Expanded(
            child: Text(mensaje, style: MatixText.small.copyWith(
              color: MatixColors.text,
            )),
          ),
        ],
      ),
    );
  }
}

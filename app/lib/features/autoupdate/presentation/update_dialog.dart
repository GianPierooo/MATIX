import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../data/update_service.dart';

/// Diálogo modal de auto-actualización.
///
/// Por qué abre el navegador en vez de instalar in-app:
///
/// Antes usábamos `ota_update`, que descargaba el APK y lanzaba el
/// instalador del sistema con `Intent.ACTION_INSTALL_PACKAGE` sobre
/// una URI `content://` de un `FileProvider`. Ese plugin invoca
/// `FileProvider.getUriForFile(context, "<pkg>.ota_update_provider", …)`
/// pero NO declara el `<provider>` en su manifest, y la app tampoco
/// lo declaraba. Resultado: `getUriForFile` lanzaba
/// `IllegalArgumentException` dentro de un `Handler.post(...)` en el
/// main looper de Android, SIN try/catch. Una excepción no atrapada
/// en el main looper mata el proceso de forma nativa — por eso la
/// app "se cerraba sola al instalar" y el error nunca llegaba al
/// `onError` de Dart (el crash es nativo, no un error del stream).
///
/// En el Huawei sin Google Play Services el handoff del instalador
/// es además frágil. La vía probada que SÍ funciona en ese device
/// es bajar el APK desde el navegador y tocar el archivo: el
/// instalador del sistema se abre con el navegador como fuente. Eso
/// es lo que hace este diálogo ahora — cero superficie de crash
/// nativo, una vía confiable.
Future<void> mostrarUpdateDialog(
  BuildContext context, {
  required UpdateDisponible info,
  required int buildLocal,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialogContent(info: info, buildLocal: buildLocal),
  );
}

class _UpdateDialogContent extends StatefulWidget {
  const _UpdateDialogContent({
    required this.info,
    required this.buildLocal,
  });
  final UpdateDisponible info;
  final int buildLocal;

  @override
  State<_UpdateDialogContent> createState() => _UpdateDialogContentState();
}

enum _Fase {
  listo,
  abierto, // navegador lanzado; instrucciones para terminar la instalación
  error, // no se pudo abrir el navegador; enlace copiable como respaldo
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  _Fase _fase = _Fase.listo;
  String? _error;
  bool _copiado = false;

  Future<void> _abrir() async {
    setState(() {
      _error = null;
      _copiado = false;
    });

    final uri = Uri.tryParse(widget.info.apkUrl);
    if (uri == null) {
      setState(() {
        _fase = _Fase.error;
        _error = 'El enlace del APK no es válido: ${widget.info.apkUrl}';
      });
      return;
    }

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (ok) {
        setState(() => _fase = _Fase.abierto);
      } else {
        setState(() {
          _fase = _Fase.error;
          _error =
              'No pude abrir el navegador en este teléfono. Copiá el '
              'enlace de abajo y pegalo a mano en tu navegador para '
              'bajar el APK.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _error = 'No pude abrir el navegador: $e';
      });
    }
  }

  Future<void> _copiarEnlace() async {
    await Clipboard.setData(ClipboardData(text: widget.info.apkUrl));
    if (!mounted) return;
    setState(() => _copiado = true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MatixColors.card,
      title: Row(
        children: [
          const Icon(
            Icons.system_update_alt,
            color: MatixColors.accent,
            size: 22,
          ),
          const SizedBox(width: MatixSpacing.l),
          Expanded(
            child: Text(
              'Nueva versión disponible',
              style: MatixText.subtitle,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tienes: build ${widget.buildLocal} · '
            'Nueva: build ${widget.info.buildNumber} (${widget.info.version})',
            style: MatixText.small,
          ),
          if (widget.info.notas.isNotEmpty) ...[
            const SizedBox(height: MatixSpacing.l),
            Container(
              padding: const EdgeInsets.all(MatixSpacing.l),
              decoration: BoxDecoration(
                color: MatixColors.bg,
                border: Border.all(color: MatixColors.hairline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.info.notas,
                style: MatixText.body,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: MatixSpacing.xl),
          _contenidoSegunFase(),
        ],
      ),
      actions: _accionesSegunFase(),
    );
  }

  Widget _contenidoSegunFase() {
    switch (_fase) {
      case _Fase.listo:
        return Text(
          'Te abro el navegador para que bajes el APK. Cuando termine '
          'la descarga, toca el archivo (o la notificación de descarga) '
          'para instalar. Si Android lo pide, permite instalar desde '
          'el navegador.',
          style: MatixText.small.copyWith(color: MatixColors.muted, height: 1.4),
        );

      case _Fase.abierto:
        return Container(
          padding: const EdgeInsets.all(MatixSpacing.l),
          decoration: BoxDecoration(
            color: MatixColors.accent.withValues(alpha: 0.12),
            border: Border.all(
              color: MatixColors.accent.withValues(alpha: 0.45),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.open_in_browser,
                    color: MatixColors.accent,
                    size: 18,
                  ),
                  const SizedBox(width: MatixSpacing.s),
                  Expanded(
                    child: Text(
                      'Descarga abierta en el navegador',
                      style: MatixText.body.copyWith(
                        color: MatixColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MatixSpacing.s),
              Text(
                '1. Espera a que el navegador termine de bajar el APK.\n'
                '2. Toca el archivo descargado (o la notificación).\n'
                '3. Si Android lo pide, permite instalar desde esa app.',
                style: MatixText.small.copyWith(height: 1.5),
              ),
              if (_copiado) ...[
                const SizedBox(height: MatixSpacing.s),
                _enlaceCopiado(),
              ],
            ],
          ),
        );

      case _Fase.error:
        return Container(
          padding: const EdgeInsets.all(MatixSpacing.l),
          decoration: BoxDecoration(
            color: MatixColors.red.withValues(alpha: 0.12),
            border: Border.all(
              color: MatixColors.red.withValues(alpha: 0.45),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error ?? 'No pude abrir el navegador.',
                style: MatixText.small.copyWith(color: MatixColors.text),
              ),
              const SizedBox(height: MatixSpacing.m),
              SelectableText(
                widget.info.apkUrl,
                style: MatixText.small.copyWith(
                  color: MatixColors.muted,
                  fontFamily: 'monospace',
                ),
              ),
              if (_copiado) ...[
                const SizedBox(height: MatixSpacing.s),
                _enlaceCopiado(),
              ],
            ],
          ),
        );
    }
  }

  Widget _enlaceCopiado() {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: MatixColors.green, size: 16),
        const SizedBox(width: MatixSpacing.s),
        Text(
          'Enlace copiado al portapapeles',
          style: MatixText.small.copyWith(color: MatixColors.green),
        ),
      ],
    );
  }

  List<Widget> _accionesSegunFase() {
    switch (_fase) {
      case _Fase.listo:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Más tarde'),
          ),
          FilledButton.icon(
            onPressed: _abrir,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Descargar e instalar'),
            style: FilledButton.styleFrom(
              backgroundColor: MatixColors.accent,
              foregroundColor: Colors.white,
            ),
          ),
        ];

      case _Fase.abierto:
        return [
          TextButton(
            onPressed: _copiarEnlace,
            child: const Text('Copiar enlace'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
        ];

      case _Fase.error:
        return [
          TextButton(
            onPressed: _copiarEnlace,
            child: const Text('Copiar enlace'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: _abrir,
            child: const Text('Reintentar'),
          ),
        ];
    }
  }
}

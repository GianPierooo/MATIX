import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../data/update_service.dart';

/// Diálogo modal que muestra los datos de la nueva versión y, al
/// confirmar, descarga el APK con barra de progreso. Cuando termina,
/// `ota_update` dispara el instalador del sistema (Android pide
/// "Instalar apps desconocidas" la primera vez si no se concedió).
///
/// Es un solo widget para que el flujo sea autocontenido — la
/// pantalla padre solo hace `showDialog(builder: (_) => UpdateDialog(...))`
/// y se desentiende.
Future<void> mostrarUpdateDialog(
  BuildContext context, {
  required UpdateDisponible info,
  required int buildLocal,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // mientras descarga, no dismiss accidental
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

enum _Fase { listo, descargando, instalando, error }

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  _Fase _fase = _Fase.listo;
  double? _progreso; // 0..1, null = indeterminado
  String? _error;

  Future<void> _iniciar() async {
    setState(() {
      _fase = _Fase.descargando;
      _progreso = 0;
      _error = null;
    });
    try {
      OtaUpdate()
          .execute(
            widget.info.apkUrl,
            destinationFilename: 'matix-${widget.info.buildNumber}.apk',
          )
          .listen(
        (event) {
          // El stream emite estados intermedios. Cuando el sistema
          // toma el APK para instalar, el diálogo queda esperando.
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final pct = double.tryParse(event.value ?? '');
              setState(() {
                _fase = _Fase.descargando;
                _progreso = pct != null ? pct / 100.0 : null;
              });
            case OtaStatus.INSTALLING:
            case OtaStatus.INSTALLATION_DONE:
              // INSTALLATION_DONE no significa que esté instalada
              // — significa que el sistema tomó el APK. El usuario
              // todavía tiene que confirmar en el instalador de
              // Android. Mostramos "instalando" para los dos.
              setState(() {
                _fase = _Fase.instalando;
                _progreso = null;
              });
            case OtaStatus.ALREADY_RUNNING_ERROR:
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
            case OtaStatus.INSTALLATION_ERROR:
              setState(() {
                _fase = _Fase.error;
                _error = event.value ?? event.status.toString();
              });
            case OtaStatus.CANCELED:
              // El usuario canceló en el diálogo del sistema —
              // simplemente cerramos sin error.
              if (mounted) Navigator.of(context).pop();
          }
        },
        onError: (e) {
          setState(() {
            _fase = _Fase.error;
            _error = e.toString();
          });
        },
      );
    } catch (e) {
      setState(() {
        _fase = _Fase.error;
        _error = e.toString();
      });
    }
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
            'Tenés: build ${widget.buildLocal} · '
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
        return const SizedBox.shrink();
      case _Fase.descargando:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _progreso == null
                  ? 'Descargando…'
                  : 'Descargando · ${(_progreso! * 100).toInt()}%',
              style: MatixText.small,
            ),
            const SizedBox(height: MatixSpacing.s),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progreso,
                color: MatixColors.accent,
                backgroundColor: MatixColors.cardHi,
                minHeight: 5,
              ),
            ),
          ],
        );
      case _Fase.instalando:
        return Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MatixColors.accent,
              ),
            ),
            const SizedBox(width: MatixSpacing.l),
            Text(
              'Abriendo el instalador del sistema…',
              style: MatixText.small,
            ),
          ],
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
          child: Text(
            _error ?? 'Algo falló al actualizar.',
            style: MatixText.small.copyWith(color: MatixColors.text),
          ),
        );
    }
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
            onPressed: _iniciar,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Descargar e instalar'),
            style: FilledButton.styleFrom(
              backgroundColor: MatixColors.accent,
              foregroundColor: Colors.white,
            ),
          ),
        ];
      case _Fase.descargando:
      case _Fase.instalando:
        // No dejamos cancelar a mitad — confunde más que ayudar.
        return const [];
      case _Fase.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: _iniciar,
            child: const Text('Reintentar'),
          ),
        ];
    }
  }
}

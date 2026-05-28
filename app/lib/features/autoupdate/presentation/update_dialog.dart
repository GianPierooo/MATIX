import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../data/update_service.dart';

/// Diálogo modal de auto-actualización.
///
/// Flujo de instalación (lo que antes fallaba silenciosamente):
///
/// 1. Chequeamos `Permission.requestInstallPackages` ANTES de
///    descargar. Si no está concedido, mostramos un paso intermedio
///    explicando lo que pasa y un CTA que abre Settings de Android
///    en la pantalla correcta (`openAppSettings()` lleva a la app,
///    de ahí el usuario toca "Permitir instalar fuentes desconocidas").
/// 2. Después de descargar, `ota_update` invoca el instalador del
///    sistema. Si falla, capturamos el `OtaStatus` exacto y lo
///    traducimos a un mensaje legible.
///
/// Causas típicas que cubrimos:
/// - Permiso no concedido → CTA "Abrir Ajustes".
/// - Firma mismatch (versión anterior firmada distinto) → mensaje
///   "Reinstalación necesaria: desinstalá Matix y abrí este APK
///   desde Archivos. Pasa solo una vez."
/// - Error de red durante la descarga → mensaje del status.
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
  pidiendoPermiso, // sin REQUEST_INSTALL_PACKAGES; CTA Ajustes
  descargando,
  instalando,
  error,
}

class _UpdateDialogContentState extends State<_UpdateDialogContent> {
  _Fase _fase = _Fase.listo;
  double? _progreso;
  String? _error;
  String? _consejo; // tip accionable bajo el error (ej. "desinstalá y reinstalá")

  Future<void> _iniciar() async {
    setState(() {
      _error = null;
      _consejo = null;
    });

    // 1) Pre-check del permiso REQUEST_INSTALL_PACKAGES. Sin esto,
    // Android 8+ rechaza la invocación al instalador y la app
    // muere silenciosa (lo que veía Gian Piero al 99%).
    final permiso = await Permission.requestInstallPackages.status;
    if (!permiso.isGranted) {
      final resultado = await Permission.requestInstallPackages.request();
      if (!resultado.isGranted) {
        if (!mounted) return;
        setState(() {
          _fase = _Fase.pidiendoPermiso;
        });
        return;
      }
    }

    // 2) Descargar e instalar.
    setState(() {
      _fase = _Fase.descargando;
      _progreso = 0;
    });
    try {
      OtaUpdate()
          .execute(
            widget.info.apkUrl,
            destinationFilename: 'matix-${widget.info.buildNumber}.apk',
          )
          .listen(
        (event) {
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final pct = double.tryParse(event.value ?? '');
              setState(() {
                _fase = _Fase.descargando;
                _progreso = pct != null ? pct / 100.0 : null;
              });
            case OtaStatus.INSTALLING:
            case OtaStatus.INSTALLATION_DONE:
              setState(() {
                _fase = _Fase.instalando;
                _progreso = null;
              });
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              setState(() {
                _fase = _Fase.pidiendoPermiso;
              });
            case OtaStatus.INSTALLATION_ERROR:
              setState(() {
                _fase = _Fase.error;
                _error = _mensajeDeStatus(event.status, event.value);
                _consejo =
                    'Esto suele pasar cuando la versión actual fue '
                    'firmada distinto al APK nuevo (típico la primera '
                    'vez tras cambiar a llave de release estable). '
                    '**Desinstalá Matix** y volvé a abrir esta '
                    'actualización desde el navegador: el APK se '
                    'instala limpio. De ahí en adelante, las próximas '
                    'OTA fluyen solas.';
              });
            case OtaStatus.ALREADY_RUNNING_ERROR:
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
              setState(() {
                _fase = _Fase.error;
                _error = _mensajeDeStatus(event.status, event.value);
              });
            case OtaStatus.CANCELED:
              if (mounted) Navigator.of(context).pop();
          }
        },
        onError: (e) {
          setState(() {
            _fase = _Fase.error;
            _error = 'Error inesperado: $e';
          });
        },
      );
    } catch (e) {
      setState(() {
        _fase = _Fase.error;
        _error = 'No pude lanzar la descarga: $e';
      });
    }
  }

  String _mensajeDeStatus(OtaStatus s, String? valor) {
    switch (s) {
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        return 'Falta el permiso de instalación.';
      case OtaStatus.INSTALLATION_ERROR:
        return 'Android rechazó la instalación del APK.';
      case OtaStatus.ALREADY_RUNNING_ERROR:
        return 'Ya hay una actualización en curso.';
      case OtaStatus.INTERNAL_ERROR:
        return 'Error interno del actualizador: ${valor ?? "sin detalle"}';
      case OtaStatus.DOWNLOAD_ERROR:
        return 'Falló la descarga: ${valor ?? "sin detalle"}';
      case OtaStatus.CHECKSUM_ERROR:
        return 'El APK descargado está corrupto. Reintentá.';
      default:
        return valor ?? s.toString();
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

      case _Fase.pidiendoPermiso:
        return Container(
          padding: const EdgeInsets.all(MatixSpacing.l),
          decoration: BoxDecoration(
            color: MatixColors.amber.withValues(alpha: 0.12),
            border: Border.all(
              color: MatixColors.amber.withValues(alpha: 0.45),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    color: MatixColors.amber,
                    size: 18,
                  ),
                  const SizedBox(width: MatixSpacing.s),
                  Text(
                    'Falta permiso de instalación',
                    style: MatixText.body.copyWith(
                      color: MatixColors.amber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MatixSpacing.s),
              Text(
                'Android exige que habilites "Instalar apps '
                'desconocidas" para Matix antes de poder actualizar. '
                'Tocá "Abrir Ajustes" → activá el toggle → volvé '
                'acá y tocá "Continuar".',
                style: MatixText.small,
              ),
            ],
          ),
        );

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
            Expanded(
              child: Text(
                'Abriendo el instalador del sistema… '
                'Confirmá en el diálogo de Android.',
                style: MatixText.small,
              ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error ?? 'Algo falló al actualizar.',
                style: MatixText.small.copyWith(color: MatixColors.text),
              ),
              if (_consejo != null) ...[
                const SizedBox(height: MatixSpacing.m),
                Text(
                  _consejo!,
                  style: MatixText.small.copyWith(
                    color: MatixColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ],
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

      case _Fase.pidiendoPermiso:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          OutlinedButton.icon(
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Abrir Ajustes'),
          ),
          FilledButton(
            onPressed: _iniciar,
            child: const Text('Continuar'),
          ),
        ];

      case _Fase.descargando:
      case _Fase.instalando:
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

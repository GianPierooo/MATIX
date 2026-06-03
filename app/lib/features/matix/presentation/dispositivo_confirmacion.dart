import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accion_dispositivo.dart';
import '../providers/dispositivo_providers.dart';
import '../providers/matix_chat_providers.dart';

/// Atiende una [AccionDispositivo] propuesta por Matix (Capa 6 · Fase 1).
///
/// Reglas de seguridad:
///  - Acciones que ENVÍAN o CREAN (`requiereConfirmacion == true`: mensaje,
///    llamada, evento) muestran una hoja de confirmación ANTES de lanzar el
///    Intent. El usuario siempre da el visto bueno.
///  - `abrir` (bajo riesgo) se ejecuta directo.
///  - `galeria` no lanza un Intent: obtiene la foto (la más reciente o una
///    elegida) y la manda al chat con el propósito, reusando el flujo de OCR.
///
/// Degradación limpia: si una acción no se puede lanzar (sin app destino,
/// permiso negado), avisa con un SnackBar; nunca crashea.
Future<void> manejarAccionDispositivo(
  BuildContext context,
  WidgetRef ref,
  AccionDispositivo accion,
) async {
  if (accion.tipo == 'galeria') {
    await _manejarGaleria(context, ref, accion);
    return;
  }

  if (accion.requiereConfirmacion) {
    final confirmado = await _mostrarHoja(context, accion);
    if (confirmado != true) return;
  }

  final servicio = ref.read(dispositivoServiceProvider);
  final resultado = await servicio.ejecutar(accion.tipo, accion.datos);
  if (!resultado.exito && context.mounted) {
    _aviso(context, resultado.mensaje ?? 'No pude completar la acción.');
  }
}

Future<void> _manejarGaleria(
  BuildContext context,
  WidgetRef ref,
  AccionDispositivo accion,
) async {
  final servicio = ref.read(dispositivoServiceProvider);
  final modo = (accion.datos['modo'] as String?) ?? 'elegir';
  final ruta = await servicio.obtenerFoto(modo);
  if (ruta == null) return; // el usuario canceló o no había foto
  if (!context.mounted) return;

  final bytes = await File(ruta).readAsBytes();
  if (bytes.length > 4 * 1024 * 1024) {
    if (context.mounted) _aviso(context, 'La foto es muy pesada (máx 4 MB).');
    return;
  }
  final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
  final proposito = (accion.datos['proposito'] as String?)?.trim();
  await ref.read(chatMatixProvider.notifier).enviar(
        (proposito == null || proposito.isEmpty)
            ? 'Mira esta foto y ayúdame con lo que muestre.'
            : proposito,
        imagenesDataUrl: [dataUrl],
        imagenPaths: [ruta],
      );
}

Future<bool?> _mostrarHoja(BuildContext context, AccionDispositivo accion) {
  final (titulo, icono, cta) = _presentacion(accion.tipo);
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Root navigator: la hoja sale por encima de manos libres (voz) cuando la
    // acción llega estando esa pantalla abierta.
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 22),
                const SizedBox(width: 10),
                Text(titulo, style: Theme.of(ctx).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (accion.resumen.isNotEmpty)
              Text(accion.resumen, style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    icon: Icon(icono, size: 18),
                    label: Text(cta),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

(String, IconData, String) _presentacion(String tipo) => switch (tipo) {
      'mensaje' => ('Enviar mensaje', Icons.send_rounded, 'Continuar'),
      'llamada' => ('Llamar', Icons.call_rounded, 'Marcar'),
      'evento' => ('Crear evento', Icons.event_rounded, 'Crear'),
      _ => ('Confirmar acción', Icons.touch_app_rounded, 'Continuar'),
    };

void _aviso(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

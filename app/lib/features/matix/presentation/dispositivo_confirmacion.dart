import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';
import '../data/accion_dispositivo.dart';
import '../providers/dispositivo_providers.dart';
import '../providers/matix_chat_providers.dart';
import 'accesibilidad_screen.dart';

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

  if (accion.tipo == 'pantalla') {
    await _manejarPantalla(context, ref, accion);
    return;
  }

  if (accion.tipo == 'whatsapp') {
    await _manejarWhatsapp(context, ref, accion);
    return;
  }

  // PC (Capa 6 · 6.1): acción consecuente en la PC. Reusa el sheet de gate y,
  // tras confirmar, la ejecuta vía el cerebro (POST /agente/ejecutar).
  if (accion.tipo == 'pc_accion') {
    await _manejarPcAccion(context, ref, accion);
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

/// Tier C.0 · PERCEPCIÓN: lee la pantalla activa (solo lectura) y la manda al
/// modelo como DATO. Indicador visible siempre: nunca lectura silenciosa.
Future<void> _manejarPantalla(
  BuildContext context,
  WidgetRef ref,
  AccionDispositivo accion,
) async {
  final lectura = await ref.read(accesibilidadServiceProvider).leer();
  if (!context.mounted) return;

  // Servicio apagado: explicar y llevar a la pantalla de activación.
  if (!lectura.activo) {
    _aviso(context, 'Necesito el permiso de accesibilidad para leer la pantalla.');
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const AccesibilidadScreen()),
    );
    return;
  }

  // Activo pero sin ventana legible: casi siempre solo se veía Matix.
  if (!lectura.ok) {
    _aviso(
      context,
      lectura.motivo == 'sin_ventana'
          ? 'Abre la app que quieres que lea y vuelve a pedírmelo.'
          : 'No pude leer la pantalla esta vez.',
    );
    return;
  }

  // Allowlist (permisiva en C.0): qué apps puede leer Matix.
  final permitido = await ref.read(pantallaAllowlistProvider).permitido(lectura.app);
  if (!context.mounted) return;
  if (!permitido) {
    _aviso(context, 'Por ahora no tengo permiso para leer esa app.');
    return;
  }

  // Indicador VISIBLE: que el usuario sepa siempre que Matix leyó la pantalla.
  _aviso(context, 'Leí la pantalla de ${_nombreApp(lectura.app)}.');

  final proposito = (accion.datos['proposito'] as String?)?.trim();
  await ref.read(chatMatixProvider.notifier).enviar(
        (proposito == null || proposito.isEmpty) ? 'Léeme la pantalla.' : proposito,
        documentoNombre: 'Pantalla activa — ${_nombreApp(lectura.app)}',
        documentoTexto: lectura.texto.isEmpty
            ? '(La pantalla no tenía texto legible.)'
            : lectura.texto,
      );
}

/// Tier C.1 · PRIMERA ACCIÓN: escribe (y, tras tu confirmación, envía) un
/// WhatsApp vía el bucle de acción blindado. El gate de envío es un overlay
/// sobre WhatsApp; el kill switch vive en la notificación.
Future<void> _manejarWhatsapp(
  BuildContext context,
  WidgetRef ref,
  AccionDispositivo accion,
) async {
  final contacto = (accion.datos['contacto'] as String?)?.trim() ?? '';
  final mensaje = (accion.datos['mensaje'] as String?)?.trim() ?? '';
  if (contacto.isEmpty || mensaje.isEmpty) {
    _aviso(context, 'Me falta el contacto o el mensaje para escribir el WhatsApp.');
    return;
  }

  final acc = ref.read(accesibilidadServiceProvider);
  if (!await acc.activa()) {
    if (!context.mounted) return;
    _aviso(context, 'Para escribir por WhatsApp necesito el permiso de accesibilidad.');
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const AccesibilidadScreen()),
    );
    return;
  }

  if (!context.mounted) return;
  _aviso(context, 'Escribiéndole a $contacto…');
  final flujo = ref.read(whatsappAccionFlujoProvider);
  final resultado = await flujo.ejecutar(
    contacto: contacto,
    mensaje: mensaje,
    onLog: (_) {}, // el log visible va por la notificación (acc.actualizarFlujo)
    confirmar: (resumen) => acc.confirmarEnvio(resumen),
  );

  // Aviso final visible (notificación) + en la app si está al frente.
  await acc.terminarFlujo(resultado.mensaje);
  if (context.mounted) _aviso(context, resultado.mensaje);
}

/// PC (Capa 6 · 6.1): ejecuta una acción consecuente en la PC TRAS la
/// confirmación del usuario. El modelo solo propuso; aquí el humano da el OK en
/// el sheet y recién entonces se ejecuta vía el cerebro (que pone confirmado=
/// true al cruzar el canal). El agente revalida todo en su borde.
Future<void> _manejarPcAccion(
  BuildContext context,
  WidgetRef ref,
  AccionDispositivo accion,
) async {
  final confirmado = await _mostrarHoja(context, accion);
  if (confirmado != true) return;

  final accionInterna = accion.datos['accion'] as String?;
  if (accionInterna == null || accionInterna.isEmpty) return;
  final args = (accion.datos['args'] as Map?)?.cast<String, dynamic>() ?? const {};

  if (context.mounted) _aviso(context, 'Haciéndolo en tu PC…');
  // Honestidad: el RESULTADO REAL va al CHAT (no solo a un toast efímero). Así
  // el usuario ve en la conversación si de verdad se abrió, o si se rechazó/
  // falló y POR QUÉ (la denylist, "no encontré la app", etc.).
  final chat = ref.read(chatMatixProvider.notifier);
  try {
    final r = await ref.read(matixClientProvider).post('/api/v1/agente/ejecutar', {
      'accion': accionInterna,
      'args': args,
    });
    final res = (r['resultado'] as Map?)?.cast<String, dynamic>() ?? const {};
    chat.agregarNotaMatix(_mensajePcResultado(accionInterna, res));
  } on MatixApiException catch (e) {
    chat.agregarNotaMatix(
      'No pude hablar con el cerebro para hacerlo en tu PC (HTTP ${e.statusCode}).',
    );
  } catch (_) {
    chat.agregarNotaMatix('No pude completar la acción en tu PC.');
  }
}

String _mensajePcResultado(String accion, Map<String, dynamic> res) {
  if (res['ok'] == true) {
    switch (accion) {
      case 'mover_archivo':
        return 'Listo, lo moví en tu PC.';
      case 'renombrar_archivo':
        return 'Listo, lo renombré.';
      case 'crear_carpeta':
        return 'Carpeta creada.';
      case 'organizar_aplicar':
        final n = res['total_movidos'] ?? 0;
        final omitidos = (res['omitidos'] as List?)?.length ?? 0;
        return omitidos > 0
            ? 'Organicé tu carpeta: moví $n archivo(s), omití $omitidos.'
            : 'Organicé tu carpeta: moví $n archivo(s).';
      // 6.2 — apps y tareas
      case 'abrir_app':
        final app = res['app'] ?? 'la app';
        return 'Abrí $app en tu PC.';
      case 'cerrar_app':
        final app = res['app'] ?? 'la app';
        if (res['tipo'] == 'nada_que_cerrar') {
          return 'No tenía $app abierta en esta sesión.';
        }
        return 'Cerré $app en tu PC.';
      case 'ejecutar_tarea':
        final abiertas = (res['abiertas'] as List?)?.length;
        if (abiertas != null) return 'Listo, abrí $abiertas app(s) para tu sesión.';
        return 'Tarea ejecutada en tu PC.';
      // 6.3 — control de pantalla: acción irreversible ya confirmada
      case 'pantalla_accion_confirmada':
        return 'Listo, hice esa acción en tu pantalla.';
      default:
        return 'Hecho en tu PC.';
    }
  }
  final tipo = res['tipo'];
  if (tipo == 'pc_desconectada') {
    return 'Tu PC no está conectada. Abre el agente y reintenta.';
  }
  if (tipo == 'destino_existe' || tipo == 'ya_existe') {
    return 'Ya existe algo con ese nombre; no lo sobreescribí.';
  }
  return (res['mensaje'] as String?) ?? 'No pude completar la acción en tu PC.';
}

/// Nombre amable a partir del paquete (último segmento), para el indicador.
String _nombreApp(String paquete) {
  if (paquete.isEmpty) return 'la app';
  const conocidas = {
    'com.whatsapp': 'WhatsApp',
    'org.telegram.messenger': 'Telegram',
    'com.instagram.android': 'Instagram',
    'com.google.android.gm': 'Gmail',
    'com.android.chrome': 'Chrome',
  };
  return conocidas[paquete] ?? paquete.split('.').last;
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
      'pc_accion' => ('Hacer en tu PC', Icons.folder_open, 'Confirmar'),
      _ => ('Confirmar acción', Icons.touch_app_rounded, 'Continuar'),
    };

void _aviso(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

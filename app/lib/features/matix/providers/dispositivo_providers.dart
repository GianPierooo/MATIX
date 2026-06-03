import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accesibilidad_service.dart';
import '../data/accion_dispositivo.dart';
import '../data/contactos_resolver.dart';
import '../data/dispositivo_service.dart';
import '../data/pantalla_allowlist.dart';
import '../data/whatsapp_accion_flujo.dart';

/// Servicio que ejecuta las acciones de teléfono (intents + galería).
final dispositivoServiceProvider =
    Provider<DispositivoService>((_) => DispositivoService());

/// Servicio de PERCEPCIÓN (Tier C.0): lee la pantalla activa (solo lectura).
final accesibilidadServiceProvider =
    Provider<AccesibilidadService>((_) => AccesibilidadService());

/// Allowlist de paquetes que Matix puede leer (escafoldado, permisivo en C.0).
final pantallaAllowlistProvider =
    Provider<PantallaAllowlist>((_) => PantallaAllowlist());

/// Resuelve nombre de contacto → número (Tier C.1).
final contactosResolverProvider =
    Provider<ContactosResolver>((_) => ContactosResolver());

/// Bucle de acción de WhatsApp (Tier C.1): abre, verifica, escribe, confirma,
/// envía — con verificación por paso.
final whatsappAccionFlujoProvider = Provider<WhatsappAccionFlujo>((ref) {
  return WhatsappAccionFlujo(
    ref.watch(accesibilidadServiceProvider),
    ref.watch(dispositivoServiceProvider),
    ref.watch(contactosResolverProvider),
  );
});

/// Acción de teléfono pendiente de atender. La capa de chat la SETEA cuando un
/// turno trae `accion_dispositivo`; la UI la OBSERVA (hoja de confirmación o
/// ejecución directa) y la vuelve a `null`. One-shot, igual que la navegación.
final accionDispositivoProvider =
    StateProvider<AccionDispositivo?>((_) => null);

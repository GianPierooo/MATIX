import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accesibilidad_service.dart';
import '../data/accion_dispositivo.dart';
import '../data/dispositivo_service.dart';
import '../data/pantalla_allowlist.dart';

/// Servicio que ejecuta las acciones de teléfono (intents + galería).
final dispositivoServiceProvider =
    Provider<DispositivoService>((_) => DispositivoService());

/// Servicio de PERCEPCIÓN (Tier C.0): lee la pantalla activa (solo lectura).
final accesibilidadServiceProvider =
    Provider<AccesibilidadService>((_) => AccesibilidadService());

/// Allowlist de paquetes que Matix puede leer (escafoldado, permisivo en C.0).
final pantallaAllowlistProvider =
    Provider<PantallaAllowlist>((_) => PantallaAllowlist());

/// Acción de teléfono pendiente de atender. La capa de chat la SETEA cuando un
/// turno trae `accion_dispositivo`; la UI la OBSERVA (hoja de confirmación o
/// ejecución directa) y la vuelve a `null`. One-shot, igual que la navegación.
final accionDispositivoProvider =
    StateProvider<AccionDispositivo?>((_) => null);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accion_dispositivo.dart';
import '../data/dispositivo_service.dart';

/// Servicio que ejecuta las acciones de teléfono (intents + galería).
final dispositivoServiceProvider =
    Provider<DispositivoService>((_) => DispositivoService());

/// Acción de teléfono pendiente de atender. La capa de chat la SETEA cuando un
/// turno trae `accion_dispositivo`; la UI la OBSERVA (hoja de confirmación o
/// ejecución directa) y la vuelve a `null`. One-shot, igual que la navegación.
final accionDispositivoProvider =
    StateProvider<AccionDispositivo?>((_) => null);

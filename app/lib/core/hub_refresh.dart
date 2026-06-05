import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/horario/providers/horario_providers.dart';
import '../features/rollover/providers/rollover_providers.dart';
import '../features/tareas/providers/tareas_providers.dart';

/// Invalida en bloque las vistas que cuentan la MISMA historia de "lo que hay
/// que hacer hoy": Tareas, plan del día y rollover. Una tarea es UNA entidad —
/// completarla o moverla desde cualquier lado tiene que reflejarse en las tres.
///
/// Antes cada call-site invalidaba solo "su" provider y eso desincronizaba el
/// hub: marcar hecho desde el plan no quitaba la tarea de la pestaña Tareas, y
/// completar desde Tareas no quitaba el bloque de "Tu día". Esto cierra el aro.
///
/// Es barato (cada provider se recarga lazy, solo si hay un widget watcheándolo)
/// y safe (no hace red por sí mismo).
void invalidarHub(WidgetRef ref) {
  ref.invalidate(tareasProvider);
  ref.invalidate(planDiaProvider);
  ref.invalidate(rolloverProvider);
}

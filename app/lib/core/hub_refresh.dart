import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/eventos/providers/eventos_providers.dart';
import '../features/horario/providers/horario_providers.dart';
import '../features/proyectos/providers/proyectos_providers.dart';
import '../features/push/providers/pendientes_providers.dart';
import '../features/rollover/providers/rollover_providers.dart';
import '../features/tareas/providers/tareas_providers.dart';

/// Refresca SISTÉMICAMENTE todas las vistas que cuentan la MISMA historia de "lo
/// que hay que hacer": Tareas, plan del día (Tu día), rollover y Proyectos (la
/// acción siguiente de un proyecto cambia al crear/completar/mover una tarea).
/// Una tarea es UNA entidad — crearla, completarla o moverla desde cualquier
/// lado tiene que reflejarse en TODAS las vistas, sin refresco manual.
///
/// REGLA: cualquier mutación (crear, completar, agendar, posponer, saltar) llama
/// a esto al terminar con éxito. Antes cada call-site invalidaba solo "su"
/// provider y eso desincronizaba el hub (agregar algo no aparecía hasta tirar a
/// refrescar). Esto cierra el aro.
///
/// Es barato (cada provider recarga lazy, solo si hay un widget watcheándolo)
/// y safe (no hace red por sí mismo).
void invalidarHub(WidgetRef ref) {
  ref.invalidate(tareasProvider);
  ref.invalidate(planDiaProvider);
  ref.invalidate(rolloverProvider);
  ref.invalidate(proyectosListProvider);
  // Pendientes de confirmar y eventos: cualquier mutación los puede afectar
  // (completar una tarea la saca de pendientes; cambiar un evento idem).
  ref.invalidate(pendientesConfirmacionProvider);
  ref.invalidate(eventosProvider);
}

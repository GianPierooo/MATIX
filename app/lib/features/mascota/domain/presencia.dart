// La presencia flotante de Matix SIEMPRE muestra lo más relevante del momento,
// leyendo el plan del día + el contexto + el reloj. Esto es AMBIENTAL (se
// actualiza solo, no interrumpe); los pings reales los dosifica la proactividad.
//
// Todo PURO y determinístico, para testear sin widgets ni red.

import '../../horario/domain/plan_dia.dart';
import 'personalidad.dart';

/// Qué está diciendo la presencia ahora mismo (para teñir el tono / animación).
enum TipoPresencia {
  saludo,
  ahora,
  siguiente,
  libre,
  pendientes,
  felicitacion,
  rollover,
  idle,
}

/// Acciones tocables que puede ofrecer la burbuja. Se mapean a chips + conducta.
enum AccionPresencia {
  hecho,
  posponer,
  saltar,
  reprogramar,
  hablemos,
  verMiDia,
  seguimos,
  // Rollover de lo no cumplido (Capa 8): mover al hueco propuesto, a otro día,
  // o soltarlo sin culpa.
  aceptarRollover,
  otroDia,
  soltar,
}

extension AccionPresenciaX on AccionPresencia {
  String get etiqueta => switch (this) {
        AccionPresencia.hecho => 'Hecho',
        AccionPresencia.posponer => 'Posponer',
        AccionPresencia.saltar => 'Saltar',
        AccionPresencia.reprogramar => 'Reprogramar',
        AccionPresencia.hablemos => 'Hablemos',
        AccionPresencia.verMiDia => 'Ver mi día',
        AccionPresencia.seguimos => 'Seguimos',
        AccionPresencia.aceptarRollover => 'Acepto',
        AccionPresencia.otroDia => 'Otro día',
        AccionPresencia.soltar => 'Lo suelto',
      };
}

/// El mensaje ambiental ya resuelto: texto + acciones + (si aplica) el bloque al
/// que apuntan las acciones de hacer/saltar.
class MensajePresencia {
  const MensajePresencia({
    required this.tipo,
    required this.texto,
    required this.acciones,
    this.tareaId,
    this.nodoId,
    this.setItemId,
  });

  final TipoPresencia tipo;
  final String texto;
  final List<AccionPresencia> acciones;
  final String? tareaId;
  final String? nodoId;
  final String? setItemId;
}

/// El bloque que cubre `ahoraMin` (si lo hay). PURO.
BloquePlan? bloqueActual(List<BloquePlan> bloques, int ahoraMin) {
  for (final b in bloques) {
    if (b.inicioMin <= ahoraMin && ahoraMin < b.finMin) return b;
  }
  return null;
}

/// El próximo bloque que empieza después de `ahoraMin` (el más cercano). PURO.
BloquePlan? bloqueSiguiente(List<BloquePlan> bloques, int ahoraMin) {
  BloquePlan? mejor;
  for (final b in bloques) {
    if (b.inicioMin > ahoraMin) {
      if (mejor == null || b.inicioMin < mejor.inicioMin) mejor = b;
    }
  }
  return mejor;
}

String _dur(int min) {
  final h = min ~/ 60;
  final m = min % 60;
  if (h > 0 && m > 0) return '${h}h ${m}min';
  if (h > 0) return '${h}h';
  return '${m}min';
}

const _acInfo = [AccionPresencia.verMiDia, AccionPresencia.hablemos];
const _acHablar = [AccionPresencia.hablemos, AccionPresencia.verMiDia];

/// Rota dentro de un pool de frases por la semilla (variedad sin repetir).
String _rot(List<String> pool, int s) => pool[s.abs() % pool.length];

/// Construye el POOL de mensajes relevantes AHORA, en orden de prioridad. El
/// primero (índice 0) es siempre el más relevante; los siguientes dan variedad
/// ambiental para que la burbuja rote y no repita. La `semilla` rota las frases.
/// Siempre devuelve al menos un mensaje (el idle por franja). PURO y testeable.
List<MensajePresencia> poolPresencia(
  PlanDia? plan,
  ContextoMascota ctx,
  DateTime ahora, {
  int semilla = 0,
}) {
  final out = <MensajePresencia>[];
  final ahoraMin = ahora.hour * 60 + ahora.minute;
  final bloques = plan?.bloques ?? const <BloquePlan>[];

  // 1) Lo que toca AHORA mismo (accionable si es tentativo).
  final actual = bloqueActual(bloques, ahoraMin);
  if (actual != null && actual.tentativo) {
    final ctxName = actual.proyecto ?? actual.skill;
    out.add(MensajePresencia(
      tipo: TipoPresencia.ahora,
      texto: ctxName != null
          ? _rot([
              'Ahora toca: ${actual.titulo} ($ctxName). ¿Le entras?',
              '${actual.titulo} es lo de ahora ($ctxName). ¿Le metemos?',
            ], semilla)
          : _rot([
              'Ahora toca: ${actual.titulo}. ¿Le entras?',
              '${actual.titulo} es lo de ahora. ¿Arrancamos?',
            ], semilla),
      acciones: const [
        AccionPresencia.hecho,
        AccionPresencia.posponer,
        AccionPresencia.saltar,
      ],
      tareaId: actual.tareaId,
      nodoId: actual.nodoId,
      setItemId: actual.setItemId,
    ));
  } else if (actual != null) {
    out.add(MensajePresencia(
      tipo: TipoPresencia.ahora,
      texto: 'Estás en ${actual.titulo}. Cuando salgas, seguimos.',
      acciones: _acInfo,
    ));
  }

  // 2) Un rato libre: aprovechable con una sugerencia del plan.
  final siguiente = bloqueSiguiente(bloques, ahoraMin);
  if (plan != null && plan.sugerencias.isNotEmpty) {
    final s = plan.sugerencias.first;
    final libre = siguiente != null ? siguiente.inicioMin - ahoraMin : null;
    final libreTxt = (libre != null && libre > 0) ? _dur(libre) : null;
    out.add(MensajePresencia(
      tipo: TipoPresencia.libre,
      texto: libreTxt != null
          ? _rot([
              'Tienes $libreTxt libre. ¿Le das a ${s.titulo}?',
              '$libreTxt para ti. Buen rato para ${s.titulo}.',
            ], semilla)
          : '¿Aprovechas un rato para ${s.titulo}?',
      acciones: _acInfo,
    ));
  }

  // 3) Lo que sigue, si está cerca.
  if (siguiente != null) {
    final falta = siguiente.inicioMin - ahoraMin;
    if (falta <= 60) {
      out.add(MensajePresencia(
        tipo: TipoPresencia.siguiente,
        texto: 'En ${_dur(falta)}: ${siguiente.titulo}.',
        acciones: _acInfo,
      ));
    }
  }

  // 4) Atrasos: "esto venció, ¿lo muevo?" (sin culpa, con reprogramar).
  if (ctx.vencidas > 0) {
    out.add(MensajePresencia(
      tipo: TipoPresencia.pendientes,
      texto: _rot([
        'Tienes ${ctx.vencidas} que se pasó de fecha. ¿La vemos sin drama?',
        'Algo venció (${ctx.vencidas}). ¿Lo muevo a hoy?',
      ], semilla),
      acciones: const [AccionPresencia.reprogramar, AccionPresencia.hablemos],
    ));
  }

  // 5) Proyecto activo sin acción siguiente: invita a definirla.
  if (ctx.proyectoSinSiguiente != null) {
    out.add(MensajePresencia(
      tipo: TipoPresencia.pendientes,
      texto: _rot([
        'A ${ctx.proyectoSinSiguiente} le falta su siguiente paso. ¿Se lo ponemos?',
        '${ctx.proyectoSinSiguiente} no tiene acción siguiente. ¿La definimos?',
      ], semilla),
      acciones: _acInfo,
    ));
  }

  // 6) Proyecto en riesgo (quieto).
  if (ctx.proyectosEnRiesgo > 0) {
    out.add(MensajePresencia(
      tipo: TipoPresencia.pendientes,
      texto: _rot([
        'Un proyecto está medio quieto. ¿Le damos un toque?',
        'Hay un proyecto esperándote. Un pasito chico y revive.',
      ], semilla),
      acciones: _acInfo,
    ));
  }

  // 7) Tu proyecto foco, cuando el día está liviano: empuja lo importante.
  if (ctx.proyectoFoco != null && ctx.tareasHoy == 0 && ctx.vencidas == 0) {
    out.add(MensajePresencia(
      tipo: TipoPresencia.ahora,
      texto: _rot([
        '${ctx.proyectoFoco} es tu prioridad. ¿Un pasito hoy?',
        'Si quieres avanzar, ${ctx.proyectoFoco} te espera.',
      ], semilla),
      acciones: _acInfo,
    ));
  }

  // 8) Carga de hoy.
  if (ctx.tareasHoy > 0) {
    out.add(MensajePresencia(
      tipo: TipoPresencia.ahora,
      texto: _rot([
        'Para hoy tienes ${ctx.tareasHoy}. Vamos con calma y las sacamos.',
        'Hoy hay ${ctx.tareasHoy} en la mira. Tú marcas el ritmo.',
      ], semilla),
      acciones: _acInfo,
    ));
  }

  // 8b) Backlog: tareas sueltas sin fecha. El planificador ya las jala a
  // huecos; el robot lo surfacea para que no mueran calladas (dosificado: es
  // un candidato más del pool que rota, no un ping).
  if (ctx.tareasSinFecha > 0) {
    final n = ctx.tareasSinFecha;
    out.add(MensajePresencia(
      tipo: TipoPresencia.pendientes,
      texto: _rot([
        'Tienes $n sin fecha sueltas. ¿Las acomodo en un hueco?',
        '$n tareas esperan turno sin fecha. ¿Les busco lugar hoy?',
      ], semilla),
      acciones: _acInfo,
    ));
  }

  // 9) Aliento ambiental (siempre disponible, da variedad).
  out.add(MensajePresencia(
    tipo: TipoPresencia.idle,
    texto: _rot([
      'Vas bien, en serio. Un paso a la vez.',
      'Acá ando contigo. Lo que necesites, me dices.',
      'Tranqui, que vamos avanzando. Confío en ti.',
    ], semilla),
    acciones: _acHablar,
  ));

  // 10) Dato/empujoncito de captura (variedad ambiental).
  out.add(MensajePresencia(
    tipo: TipoPresencia.idle,
    texto: _rot([
      'Tip: lo que anotas al toque no se te pierde. Yo me encargo.',
      '¿Algo en la cabeza? Dímelo y lo guardo.',
      'Registrar rápido es media batalla ganada.',
    ], semilla),
    acciones: _acHablar,
  ));

  // 11) Idle por franja del día (siempre presente: asegura pool no vacío).
  final franja = franjaDe(ahora.hour);
  final txt = switch (franja) {
    FranjaDia.manana => _rot([
        'Buen día. Acá ando para arrancar contigo.',
        'Arrancamos el día. ¿Por dónde empezamos?',
      ], semilla),
    FranjaDia.tarde => _rot([
        'Acá ando. ¿En qué te ayudo?',
        'Sigue la tarde. ¿Le entramos a algo?',
      ], semilla),
    FranjaDia.noche => ctx.hechasHoy > 0
        ? _rot([
            'Buen día de trabajo. Cuando quieras, a descansar.',
            'Cerraste cosas hoy. Bien ahí, causa.',
          ], semilla)
        : _rot([
            'Día suave. Acá si me necesitas.',
            'Noche tranquila. Acá ando.',
          ], semilla),
  };
  out.add(MensajePresencia(
    tipo: TipoPresencia.idle,
    texto: txt,
    acciones: _acHablar,
  ));

  return out;
}

/// El corazón de la presencia: dado el plan, el contexto y la hora, devuelve UN
/// mensaje del pool. `rotacion` avanza por el pool (variedad ambiental que cambia
/// sola); en 0 entrega el más relevante. PURO y testeable.
MensajePresencia mensajePresencia(
  PlanDia? plan,
  ContextoMascota ctx,
  DateTime ahora, {
  int rotacion = 0,
}) {
  final pool = poolPresencia(plan, ctx, ahora, semilla: rotacion);
  return pool[rotacion.abs() % pool.length];
}

/// El mensaje ACCIONABLE de ahora (el que apunta a una tarea/bloque concreto),
/// si lo hay. Lo usa el menú del robot para ofrecer Hacer/Posponer/Saltar aunque
/// la burbuja esté rotando en un mensaje ambiental. PURO.
MensajePresencia? accionableActual(
  PlanDia? plan,
  ContextoMascota ctx,
  DateTime ahora,
) {
  for (final m in poolPresencia(plan, ctx, ahora)) {
    if (m.tareaId != null || m.nodoId != null || m.setItemId != null) return m;
  }
  return null;
}

/// Mensaje de celebración cuando cierras algo (lo dispara la presencia un ratito
/// al detectar avance). PURO.
MensajePresencia felicitacionPresencia(ContextoMascota ctx, {int semilla = 0}) {
  final texto = ctx.hechasHoy >= 3
      ? '¡${ctx.hechasHoy} cerradas hoy! Estás on fire.'
      : (semilla.isEven
          ? '¡Una menos! Así se avanza, causa.'
          : '¡Listo! Cada cosa cerrada suma.');
  return MensajePresencia(
    tipo: TipoPresencia.felicitacion,
    texto: texto,
    acciones: const [AccionPresencia.seguimos],
  );
}

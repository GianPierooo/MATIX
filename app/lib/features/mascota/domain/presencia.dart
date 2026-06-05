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
  idle,
}

/// Acciones tocables que puede ofrecer la burbuja. Se mapean a chips + conducta.
enum AccionPresencia { hecho, saltar, hablemos, verMiDia, seguimos }

extension AccionPresenciaX on AccionPresencia {
  String get etiqueta => switch (this) {
        AccionPresencia.hecho => 'Hecho',
        AccionPresencia.saltar => 'Saltar',
        AccionPresencia.hablemos => 'Hablemos',
        AccionPresencia.verMiDia => 'Ver mi día',
        AccionPresencia.seguimos => 'Seguimos',
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

/// El corazón de la presencia: dado el plan, el contexto y la hora, devuelve el
/// mensaje ambiental más relevante AHORA. Orden de prioridad: lo que pasa ahora
/// → un rato libre inminente → lo que sigue → pendientes/atrasos → idle por
/// franja. PURO y testeable.
MensajePresencia mensajePresencia(
  PlanDia? plan,
  ContextoMascota ctx,
  DateTime ahora,
) {
  final ahoraMin = ahora.hour * 60 + ahora.minute;
  final bloques = plan?.bloques ?? const <BloquePlan>[];

  // 1) Lo que toca AHORA mismo.
  final actual = bloqueActual(bloques, ahoraMin);
  if (actual != null && actual.tentativo) {
    final ctxName = actual.proyecto ?? actual.skill;
    return MensajePresencia(
      tipo: TipoPresencia.ahora,
      texto: ctxName != null
          ? 'Ahora toca: ${actual.titulo} ($ctxName). ¿Le entras?'
          : 'Ahora toca: ${actual.titulo}. ¿Le entras?',
      acciones: const [
        AccionPresencia.hecho,
        AccionPresencia.saltar,
        AccionPresencia.hablemos,
      ],
      tareaId: actual.tareaId,
      nodoId: actual.nodoId,
      setItemId: actual.setItemId,
    );
  }
  if (actual != null) {
    return MensajePresencia(
      tipo: TipoPresencia.ahora,
      texto: 'Estás en ${actual.titulo}. Cuando salgas, seguimos.',
      acciones: _acInfo,
    );
  }

  // 2) Un rato libre: aprovechable con una sugerencia del plan.
  final siguiente = bloqueSiguiente(bloques, ahoraMin);
  if (plan != null && plan.sugerencias.isNotEmpty) {
    final s = plan.sugerencias.first;
    final libre = siguiente != null ? siguiente.inicioMin - ahoraMin : null;
    final libreTxt = (libre != null && libre > 0) ? _dur(libre) : null;
    return MensajePresencia(
      tipo: TipoPresencia.libre,
      texto: libreTxt != null
          ? 'Tienes $libreTxt libre. ¿Le das a ${s.titulo}?'
          : '¿Aprovechas un rato para ${s.titulo}?',
      acciones: _acInfo,
    );
  }

  // 3) Lo que sigue, si está cerca.
  if (siguiente != null) {
    final falta = siguiente.inicioMin - ahoraMin;
    if (falta <= 60) {
      return MensajePresencia(
        tipo: TipoPresencia.siguiente,
        texto: 'En ${_dur(falta)}: ${siguiente.titulo}.',
        acciones: _acInfo,
      );
    }
  }

  // 4) Pendientes / atrasos, sin culpa.
  if (ctx.vencidas > 0) {
    return MensajePresencia(
      tipo: TipoPresencia.pendientes,
      texto: 'Tienes ${ctx.vencidas} que se pasó de fecha. ¿La vemos sin drama?',
      acciones: _acInfo,
    );
  }
  if (ctx.proyectosEnRiesgo > 0) {
    return const MensajePresencia(
      tipo: TipoPresencia.pendientes,
      texto: 'Un proyecto está medio quieto. ¿Le damos un toque?',
      acciones: _acInfo,
    );
  }
  if (ctx.tareasHoy > 0) {
    return MensajePresencia(
      tipo: TipoPresencia.ahora,
      texto: 'Para hoy tienes ${ctx.tareasHoy}. Vamos con calma y las sacamos.',
      acciones: _acInfo,
    );
  }

  // 5) Idle por franja del día (vivo pero tranquilo).
  final franja = franjaDe(ahora.hour);
  final texto = switch (franja) {
    FranjaDia.manana => 'Buen día. Acá ando para arrancar contigo.',
    FranjaDia.tarde => 'Acá ando. ¿En qué te ayudo?',
    FranjaDia.noche => ctx.hechasHoy > 0
        ? 'Buen día de trabajo. Cuando quieras, a descansar.'
        : 'Día suave. Acá si me necesitas.',
  };
  return MensajePresencia(
    tipo: TipoPresencia.idle,
    texto: texto,
    acciones: const [AccionPresencia.hablemos, AccionPresencia.verMiDia],
  );
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

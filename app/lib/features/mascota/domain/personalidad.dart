// La voz de Matix como mascota: cálida, de pana, con su gracia, tú peruano.
// NUNCA culpalona ni pesada. Acá vive el COPY (templates + contexto), no
// llamadas al modelo: el saludo y las apariciones son rápidas y baratas.
//
// Todo es PURO y determinístico (rota por `semilla`) para poder testearlo.

/// Franja del día, para teñir el saludo.
enum FranjaDia { manana, tarde, noche }

FranjaDia franjaDe(int hora) {
  if (hora < 12) return FranjaDia.manana;
  if (hora < 19) return FranjaDia.tarde;
  return FranjaDia.noche;
}

/// Tipo de aparición de la mascota. El saludo y la despedida son los bordes del
/// día; el resto son apariciones interactivas tipo mascota (la versión buena).
enum TipoMascota {
  saludo,
  despedida,
  aliento,
  comentario,
  felicitacion,
  empujoncito,
}

/// Lo que sabe la mascota del momento para no hablar genérico. Liviano: sale de
/// providers que ya están cargados (tareas, proyectos).
class ContextoMascota {
  const ContextoMascota({
    this.tareasHoy = 0,
    this.vencidas = 0,
    this.hechasHoy = 0,
    this.proyectosActivos = 0,
    this.proyectosEnRiesgo = 0,
    this.proyectoFoco,
    this.proyectoSinSiguiente,
  });

  final int tareasHoy;
  final int vencidas;
  final int hechasHoy;
  final int proyectosActivos;
  final int proyectosEnRiesgo;

  /// Nombre del proyecto activo top (el de mayor prioridad), para mensajes que
  /// invitan a empujar lo importante. `null` si no hay proyectos activos.
  final String? proyectoFoco;

  /// Nombre de un proyecto activo SIN acción siguiente definida: candidato a
  /// "ponle su siguiente paso". `null` si todos la tienen.
  final String? proyectoSinSiguiente;

  static const vacio = ContextoMascota();
}

/// Un mensaje listo para pintar en la tarjeta o la burbuja: el texto + las
/// opciones tocables (chips). La primera opción suele abrir el chat.
class MensajeMascota {
  const MensajeMascota({
    required this.tipo,
    required this.texto,
    this.opciones = const ['Hablemos', 'Ahora no'],
  });

  final TipoMascota tipo;
  final String texto;
  final List<String> opciones;
}

String _rot(List<String> pool, int semilla) => pool[semilla.abs() % pool.length];

/// Saludo al entrar: cálido, con un toque de contexto. Para la tarjeta de Inicio.
MensajeMascota saludo(FranjaDia franja, ContextoMascota ctx, {int semilla = 0}) {
  final hola = switch (franja) {
    FranjaDia.manana => _rot(
        ['Buenas, ya es de día', '¡Arriba! Buenos días', 'Buen día, causa'],
        semilla),
    FranjaDia.tarde => _rot(
        ['Buenas tardes', 'Qué tal la tarde', 'Buenas, sigue el día'],
        semilla),
    FranjaDia.noche => _rot(
        ['Buenas noches', 'Ya de noche, tranqui', 'Buenas, cerrando el día'],
        semilla),
  };
  final detalle = _detalleContexto(ctx, franja, semilla);
  return MensajeMascota(
    tipo: TipoMascota.saludo,
    texto: detalle == null ? '$hola. Acá ando si me necesitas.' : '$hola. $detalle',
    opciones: const ['Hablemos', 'Ver mi día'],
  );
}

String? _detalleContexto(ContextoMascota ctx, FranjaDia franja, int semilla) {
  if (ctx.vencidas > 0) {
    return _rot([
      'Tienes ${ctx.vencidas} que se te pasó de fecha; cuando quieras la vemos sin drama.',
      'Quedaron ${ctx.vencidas} atrás, pero nada que no se pueda retomar.',
    ], semilla);
  }
  if (ctx.tareasHoy > 0) {
    return _rot([
      'Para hoy tienes ${ctx.tareasHoy}. Vamos con calma y las sacamos.',
      'Hoy hay ${ctx.tareasHoy} en la mira. Tú marcas el ritmo.',
    ], semilla);
  }
  if (franja == FranjaDia.noche) {
    return _rot([
      'No hay pendientes para hoy. Buen momento para soltar.',
      'Día limpio. Descansa que te lo ganaste.',
    ], semilla);
  }
  return _rot([
    'Hoy lo tienes libre. Lo llenamos o lo disfrutas, tú decides.',
    'Sin pendientes por ahora. Acá ando para lo que salga.',
  ], semilla);
}

/// Despedida al salir: corta y cálida.
MensajeMascota despedida(FranjaDia franja, {int semilla = 0}) {
  final texto = switch (franja) {
    FranjaDia.noche => _rot(
        ['Ya, a descansar. Nos vemos mañana.', 'Chau, duerme bien causa.'],
        semilla),
    _ => _rot(
        ['Ya nos vemos, cuídate.', 'Chau, acá ando cuando vuelvas.', 'Listo, nos vemos al toque.'],
        semilla),
  };
  return MensajeMascota(tipo: TipoMascota.despedida, texto: texto, opciones: const []);
}

/// Elige QUÉ tipo de aparición toca según el contexto (no solo tareas):
/// felicita si hubo avance, empuja suave si hay algo en riesgo, y si no, alienta
/// o comenta. PURO.
TipoMascota elegirAparicion(ContextoMascota ctx, {int semilla = 0}) {
  if (ctx.hechasHoy >= 1 && ctx.vencidas == 0) return TipoMascota.felicitacion;
  if (ctx.proyectosEnRiesgo > 0 || ctx.vencidas > 0) return TipoMascota.empujoncito;
  // Sin señales fuertes: alterna entre aliento y comentario para variar.
  return semilla.isEven ? TipoMascota.aliento : TipoMascota.comentario;
}

/// Genera el mensaje de una aparición interactiva. Nunca culpalón. PURO.
MensajeMascota aparicion(TipoMascota tipo, ContextoMascota ctx, {int semilla = 0}) {
  final texto = switch (tipo) {
    TipoMascota.felicitacion => ctx.hechasHoy >= 3
        ? _rot([
            '¡Oye, ${ctx.hechasHoy} cerradas hoy! Estás on fire.',
            'Llevas ${ctx.hechasHoy} hoy. Así se hace, causa.',
          ], semilla)
        : _rot([
            '¡Una menos! Cada cosa cerrada suma.',
            'Avanzaste hoy y eso cuenta. Bien ahí.',
          ], semilla),
    TipoMascota.empujoncito => ctx.proyectosEnRiesgo > 0
        ? _rot([
            'Uno de tus proyectos está medio quieto. ¿Le damos un toque?',
            'Hay un proyecto esperándote. Un pasito chico y revive.',
          ], semilla)
        : _rot([
            'Quedó algo pendiente, pero sin presión. ¿Lo vemos un ratito?',
            'Hay algo por retomar. Cuando estés, yo te acompaño.',
          ], semilla),
    TipoMascota.aliento => _rot([
        'Vas bien, en serio. Un paso a la vez.',
        'Acá ando contigo. Lo que necesites, me dices.',
        'Tranqui, que vamos avanzando. Confío en ti.',
      ], semilla),
    TipoMascota.comentario => _rot([
        '¿Sabías que registrar al toque es media batalla ganada?',
        'Pequeño dato: lo que anotas, no se te pierde. Yo me encargo.',
        'Estoy por acá, atento. Cuéntame qué traes.',
      ], semilla),
    // saludo/despedida tienen sus propias funciones; fallback sano.
    _ => 'Acá ando si me necesitas.',
  };
  return MensajeMascota(
    tipo: tipo,
    texto: texto,
    opciones: tipo == TipoMascota.felicitacion
        ? const ['Seguimos', 'Gracias']
        : const ['Hablemos', 'Ahora no'],
  );
}

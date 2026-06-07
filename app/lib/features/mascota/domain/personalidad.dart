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

/// Modo/persona del robot, alineado a las ANCLAS del usuario (despertar/dormir
/// del horario), no al horario de silencio de los pings. Si despiertas a las 7,
/// a las 7:42 SIEMPRE es de día — aunque el silencio de notificaciones llegue
/// hasta las 8.
///
/// - `dormido`: antes de la hora de despertar o después de la de dormir; el
///   robot calla y solo asoma muy bajito si lo tocas.
/// - `manana`: desde despertar hasta el mediodía.
/// - `tarde`: desde el mediodía hasta 2h antes de la hora de dormir.
/// - `noche`: en las últimas 2h antes de dormir; tono de cierre.
enum FranjaPersona { dormido, manana, tarde, noche }

/// Decide la franja persona a partir de la hora actual y de las anclas. PURO.
/// `despertar` y `dormir` son horas enteras [0..24]. Robusto a configuraciones
/// raras: si `despertar >= dormir`, se trata como "siempre despierto" (caemos
/// a la franja por reloj sin marcar `dormido`).
FranjaPersona franjaPersonaDe(
  int hora, {
  required int despertar,
  required int dormir,
}) {
  final d = despertar.clamp(0, 23);
  final n = dormir.clamp(0, 24);
  if (d < n) {
    // Config normal (despierta < duerme). Fuera de [despertar, dormir) =
    // dormido; las últimas 2h antes de dormir = noche (cerrando el día).
    if (hora < d || hora >= n) return FranjaPersona.dormido;
    final inicioNoche = (n - 2).clamp(d + 1, n);
    if (hora >= inicioNoche) return FranjaPersona.noche;
  } else {
    // Anclas inválidas (despierta >= duerme): NO encerramos al usuario en
    // "dormido" todo el día — caemos a la franja por reloj, con la noche
    // tarde-noche por defecto.
    if (hora >= 21 || hora < 5) return FranjaPersona.noche;
  }
  if (hora < 12) return FranjaPersona.manana;
  return FranjaPersona.tarde;
}

/// Convierte la franja persona en la `FranjaDia` que usa el copy del saludo.
/// `dormido` → `noche` (la frase nocturna es la más adecuada si te asoma).
FranjaDia franjaDiaDePersona(FranjaPersona p) => switch (p) {
      FranjaPersona.manana => FranjaDia.manana,
      FranjaPersona.tarde => FranjaDia.tarde,
      FranjaPersona.noche => FranjaDia.noche,
      FranjaPersona.dormido => FranjaDia.noche,
    };

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
    this.tareasSinFecha = 0,
    this.proyectoFoco,
    this.proyectoSinSiguiente,
  });

  final int tareasHoy;
  final int vencidas;
  final int hechasHoy;
  final int proyectosActivos;
  final int proyectosEnRiesgo;

  /// Tareas en el BACKLOG: sin fecha y sin bloque agendado. El planificador ya
  /// las jala a huecos, y el robot las surfacea para que no mueran calladas.
  final int tareasSinFecha;

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

/// Concordancia de número para las plantillas con conteo: [uno] si n == 1,
/// [varios] en cualquier otro caso. Evita el "Tienes 2 que se te pasó" (debe
/// ser "se te pasaron") y el "1 tareas" (debe ser "1 tarea"). PURO.
String plural(int n, String uno, String varios) => n == 1 ? uno : varios;

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
    final n = ctx.vencidas;
    return _rot([
      'Tienes $n que se te ${plural(n, "pasó", "pasaron")} de fecha; '
          'cuando quieras ${plural(n, "la", "las")} vemos sin drama.',
      '${plural(n, "Quedó", "Quedaron")} $n atrás, pero nada que no se pueda retomar.',
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

/// Intensidad de los avisos de rendición de cuentas / asistencia. El dial vive
/// en Ajustes; arranca en ALTO ('intenso', lo que el dueño quiere) y se baja
/// para calibrarlo viviéndolo. La fuerza está en la insistencia y la presencia,
/// nunca en el tono: el contenido siempre pregunta directo, sin reproche.
///
/// El mapeo a mecanismos Android (heads-up / persistente / full-screen) es PURO
/// y testeable: el servicio de notificaciones lo aplica al construir la noti.
enum IntensidadNotif {
  suave,
  medio,
  intenso,
  maximo;

  static IntensidadNotif fromJson(String? s) => switch (s) {
        'suave' => IntensidadNotif.suave,
        'medio' => IntensidadNotif.medio,
        'maximo' => IntensidadNotif.maximo,
        _ => IntensidadNotif.intenso, // default ALTO
      };

  String toJson() => name;

  String get etiqueta => switch (this) {
        IntensidadNotif.suave => 'Suave',
        IntensidadNotif.medio => 'Medio',
        IntensidadNotif.intenso => 'Intenso',
        IntensidadNotif.maximo => 'Máximo',
      };

  String get descripcion => switch (this) {
        IntensidadNotif.suave =>
          'Notificación estándar. Llega sin saltar ni insistir.',
        IntensidadNotif.medio =>
          'Salta arriba (heads-up) con sonido y vibración.',
        IntensidadNotif.intenso =>
          'Heads-up + se queda fija hasta resolver, y re-insiste si la ignoras.',
        IntensidadNotif.maximo =>
          'Lo crítico vencido aparece como alarma sobre lo que uses, '
              're-insiste seguido y no se va hasta resolver.',
      };
}

// Canales Android por importancia. El heads-up lo decide la importancia del
// canal (no se puede subir por-notificación en Android 8+), por eso hay varios.
const String canalSuave = 'matix_suave'; // importancia default → sin heads-up
const String canalAvisos = 'matix_recordatorios'; // alta → heads-up (existente)
const String canalCritico = 'matix_critico'; // máxima → habilita full-screen

/// El mecanismo Android resultante para una noti, según la intensidad y si es
/// algo CRÍTICO (tarea vencida en el último nivel). PURO.
class MecanismoNotif {
  const MecanismoNotif({
    required this.canal,
    required this.headsUp,
    required this.persistente,
    required this.fullScreen,
  });

  /// Canal (define la importancia → si hace heads-up).
  final String canal;

  /// Salta arriba como pop (gobernado por la importancia del canal).
  final bool headsUp;

  /// `ongoing`: no se puede deslizar; se va al resolver con un botón.
  final bool persistente;

  /// `fullScreenIntent`: aparece sobre lo que estés usando, como una alarma.
  final bool fullScreen;
}

/// Mapea intensidad (+ si es crítico vencido) al mecanismo Android. PURO.
///
/// - suave  → estándar (sin heads-up, sin persistir, sin full-screen).
/// - medio  → heads-up.
/// - intenso→ heads-up + persistente.
/// - máximo → heads-up + persistente; y SOLO si es crítico, full-screen (canal
///   crítico). El silencio nocturno lo corta antes en el cerebro: ni el máximo
///   dispara full-screen mientras duermes (no se manda push siquiera).
MecanismoNotif mecanismoDe(IntensidadNotif i, {bool critico = false}) =>
    switch (i) {
      IntensidadNotif.suave => const MecanismoNotif(
          canal: canalSuave,
          headsUp: false,
          persistente: false,
          fullScreen: false,
        ),
      IntensidadNotif.medio => const MecanismoNotif(
          canal: canalAvisos,
          headsUp: true,
          persistente: false,
          fullScreen: false,
        ),
      IntensidadNotif.intenso => const MecanismoNotif(
          canal: canalAvisos,
          headsUp: true,
          persistente: true,
          fullScreen: false,
        ),
      IntensidadNotif.maximo => MecanismoNotif(
          canal: critico ? canalCritico : canalAvisos,
          headsUp: true,
          persistente: true,
          fullScreen: critico,
        ),
    };

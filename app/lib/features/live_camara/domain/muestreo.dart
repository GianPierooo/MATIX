// Muestreo inteligente + topes de costo de la cámara en vivo.
//
// La sesión en vivo es la MÁS CARA, así que el costo se controla en origen
// (acá, en el teléfono): solo se mandan al modelo los frames que pasan el
// filtro de intervalo + cambio de escena, con topes duros de frames/minuto y de
// duración de sesión, y auto-corte si no hay cambios. Esta lógica es PURA y
// testeable; el loop de cámara la consume.

/// Parámetros del muestreo y los topes. Defaults conservadores.
class PoliticaMuestreo {
  const PoliticaMuestreo({
    this.intervalo = const Duration(seconds: 3),
    this.topeFramesPorMinuto = 18,
    this.topeSesion = const Duration(minutes: 3),
    this.umbralCambio = 12, // diferencia media de gris (0..255)
    this.estaticosParaAutostop = 5, // frames seguidos sin cambio → corta
  });

  final Duration intervalo;
  final int topeFramesPorMinuto;
  final Duration topeSesion;
  final int umbralCambio;
  final int estaticosParaAutostop;
}

/// Diferencia media (0..255) entre dos firmas de frame (vectores de gris del
/// mismo largo). Si faltan o no calzan, devuelve el máximo (255 = cambio total).
double diferenciaFrames(List<int>? a, List<int>? b) {
  if (a == null || b == null || a.isEmpty || a.length != b.length) return 255;
  var suma = 0;
  for (var i = 0; i < a.length; i++) {
    suma += (a[i] - b[i]).abs();
  }
  return suma / a.length;
}

/// ¿La escena cambió lo suficiente vs la última enviada? (Sin previa → sí.)
bool hayCambioSignificativo(List<int>? previa, List<int> actual, int umbral) =>
    previa == null || diferenciaFrames(previa, actual) >= umbral;

/// Por qué NO se envía un frame (para el indicador / debug).
enum MotivoNoEnvio { intervalo, topeMinuto, sinCambio }

class DecisionMuestreo {
  const DecisionMuestreo(this.enviar, [this.motivo]);
  final bool enviar;
  final MotivoNoEnvio? motivo;
}

/// Decide si ESTE frame se manda al modelo. Orden: respeta el intervalo, luego
/// el tope por minuto, luego exige cambio de escena. PURA.
DecisionMuestreo decidirEnvio({
  required DateTime ahora,
  required DateTime? ultimoEnvio,
  required bool hayCambio,
  required int framesUltimoMinuto,
  required PoliticaMuestreo politica,
}) {
  if (ultimoEnvio != null &&
      ahora.difference(ultimoEnvio) < politica.intervalo) {
    return const DecisionMuestreo(false, MotivoNoEnvio.intervalo);
  }
  if (framesUltimoMinuto >= politica.topeFramesPorMinuto) {
    return const DecisionMuestreo(false, MotivoNoEnvio.topeMinuto);
  }
  if (!hayCambio) return const DecisionMuestreo(false, MotivoNoEnvio.sinCambio);
  return const DecisionMuestreo(true);
}

/// Cuántos envíos cayeron en el último minuto (ventana deslizante). PURA.
int framesEnUltimoMinuto(List<DateTime> envios, DateTime ahora) =>
    envios.where((t) => ahora.difference(t) < const Duration(minutes: 1)).length;

/// Por qué se cortó la sesión sola.
enum RazonCorte { topeSesion, sinCambios }

class Corte {
  const Corte(this.cortar, [this.razon]);
  final bool cortar;
  final RazonCorte? razon;
}

/// ¿La sesión debe auto-cortarse? Por tope de duración o por quedarse sin
/// cambios (cámara quieta / olvidada). PURA — el guardrail anti-cuenta-sorpresa.
Corte debeCortar({
  required DateTime inicio,
  required DateTime ahora,
  required int estaticosSeguidos,
  required PoliticaMuestreo politica,
}) {
  if (ahora.difference(inicio) >= politica.topeSesion) {
    return const Corte(true, RazonCorte.topeSesion);
  }
  if (estaticosSeguidos >= politica.estaticosParaAutostop) {
    return const Corte(true, RazonCorte.sinCambios);
  }
  return const Corte(false);
}

// Costos aproximados (USD). La visión gpt-4o-mini en detail=low es barata; el
// TTS (tts-1, $15 / 1M chars) suele pesar más. Es un ESTIMADO para dar noción.
const double kCostoFrameUsd = 0.00005;
const double kCostoTtsPorChar = 15 / 1000000;

double costoEstimadoUsd({
  required int framesEnviados,
  required int caracteresTts,
}) =>
    framesEnviados * kCostoFrameUsd + caracteresTts * kCostoTtsPorChar;

// Lógica PURA del overlay del wake word (sin Flutter ni canales nativos, para
// testear sin device). Decide cuándo "Oye Matix" debe responder con un overlay
// flotante encima de otra app en vez de abrir Matix a pantalla completa, y
// modela la máquina de estados de la sesión del overlay.

/// Qué superficie usar cuando se dispara el wake word.
enum SuperficieWake {
  /// Overlay flotante encima de la app de adelante (no la mata).
  overlay,

  /// Activity de Matix a pantalla completa (comportamiento clásico).
  fullscreen,
}

/// Decide la superficie. El overlay solo procede si TODO se cumple: el usuario
/// lo habilitó, concedió el permiso "mostrar sobre otras apps", y hay OTRA app
/// en primer plano (Matix está en background). Si Matix ya está al frente, abrir
/// a pantalla completa es lo natural. Si falta el permiso o está deshabilitado,
/// DEGRADA a fullscreen (el comportamiento actual). PURA.
SuperficieWake superficieParaWake({
  required bool overlayHabilitado,
  required bool overlayPermitido,
  required bool appEnPrimerPlano,
}) {
  if (overlayHabilitado && overlayPermitido && !appEnPrimerPlano) {
    return SuperficieWake.overlay;
  }
  return SuperficieWake.fullscreen;
}

/// Por qué el wake cayó a fullscreen (para avisar honesto al usuario la primera
/// vez). `null` si no hubo degradación (overlay procedió o el usuario no lo
/// quería). PURA.
String? motivoDegradacion({
  required bool overlayHabilitado,
  required bool overlayPermitido,
  required bool appEnPrimerPlano,
}) {
  if (!overlayHabilitado) return null; // el usuario no pidió overlay
  if (appEnPrimerPlano) return null; // ya estás en Matix; fullscreen es normal
  if (!overlayPermitido) {
    return 'Para responder en una ventanita encima necesito el permiso de '
        '«mostrar sobre otras apps». Sin él abro Matix completo.';
  }
  return null;
}

/// Fase visible del overlay (espejo simplificado de FaseManosLibres, para que el
/// shell nativo muestre el estado sin conocer la pipeline).
enum FaseOverlay { abriendo, escuchando, pensando, hablando, cerrado }

/// Estado de la sesión del overlay. La sesión NO es persistente: nace al wake y
/// muere al cerrar (o al expandir a pantalla completa).
class EstadoVozOverlay {
  const EstadoVozOverlay({this.visible = false, this.fase = FaseOverlay.cerrado});

  final bool visible;
  final FaseOverlay fase;

  static const inactivo = EstadoVozOverlay();

  EstadoVozOverlay copyWith({bool? visible, FaseOverlay? fase}) =>
      EstadoVozOverlay(
        visible: visible ?? this.visible,
        fase: fase ?? this.fase,
      );

  @override
  bool operator ==(Object other) =>
      other is EstadoVozOverlay &&
      other.visible == visible &&
      other.fase == fase;

  @override
  int get hashCode => Object.hash(visible, fase);
}

/// Transiciones PURAS de la máquina de estados del overlay. Centralizadas para
/// testear el flujo (abrir → fases → cerrar/expandir) sin canales ni widgets.
class TransicionesOverlay {
  const TransicionesOverlay._();

  /// Al disparar el wake con superficie overlay: visible, abriendo.
  static EstadoVozOverlay abrir() =>
      const EstadoVozOverlay(visible: true, fase: FaseOverlay.abriendo);

  /// La pipeline avanzó de fase (escuchando/pensando/hablando).
  static EstadoVozOverlay enFase(EstadoVozOverlay actual, FaseOverlay fase) {
    if (!actual.visible) return actual; // ya cerrado, no resucita
    return actual.copyWith(fase: fase);
  }

  /// Cerrar (el usuario tocó X o terminó la sesión): invisible, cerrado.
  static EstadoVozOverlay cerrar() => EstadoVozOverlay.inactivo;

  /// Expandir a Matix completo: la sesión sigue viva en la pantalla, el overlay
  /// se va (no duplicamos). Mismo estado final visible-falso que cerrar.
  static EstadoVozOverlay expandir() => EstadoVozOverlay.inactivo;
}

/// Traduce la fase de manos libres (string del notifier) a la fase del overlay.
/// PURA; tolerante a fases que el overlay agrupa (iniciando→abriendo, etc.).
FaseOverlay faseOverlayDe(String faseManosLibres) {
  switch (faseManosLibres) {
    case 'escuchando':
      return FaseOverlay.escuchando;
    case 'transcribiendo':
    case 'pensando':
      return FaseOverlay.pensando;
    case 'hablando':
      return FaseOverlay.hablando;
    case 'inactivo':
    case 'enPausa':
    case 'error':
      return FaseOverlay.cerrado;
    default:
      return FaseOverlay.abriendo;
  }
}

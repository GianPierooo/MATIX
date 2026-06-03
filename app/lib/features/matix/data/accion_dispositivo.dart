/// Acción de teléfono propuesta por el cerebro (Capa 6 · Fase 1).
///
/// El cerebro NO ejecuta acciones del dispositivo: sus tools
/// (`redactar_mensaje`, `iniciar_llamada`, `crear_evento_telefono`,
/// `abrir_en_telefono`, `leer_galeria`) devuelven este bloque en
/// `ChatResponse.accion_dispositivo`. La app lo recibe, pide confirmación al
/// usuario cuando hace falta, y lanza el Intent nativo correspondiente
/// (`DispositivoService`). Espeja el patrón de `navegacion`.
class AccionDispositivo {
  const AccionDispositivo({
    required this.tipo,
    required this.datos,
    required this.resumen,
    required this.requiereConfirmacion,
  });

  /// `mensaje` · `llamada` · `evento` · `abrir` · `galeria`.
  final String tipo;

  /// Carga útil específica de cada tipo (canal, numero, titulo, objetivo…).
  final Map<String, dynamic> datos;

  /// Frase corta para mostrar en la hoja de confirmación
  /// («Enviar WhatsApp a María: "¿nos vemos?"»).
  final String resumen;

  /// `true` para acciones que ENVÍAN o CREAN (mensaje, llamada, evento): la app
  /// muestra una hoja de confirmación antes de lanzar el Intent. `false` para
  /// abrir/galería (bajo riesgo): se ejecutan directo.
  final bool requiereConfirmacion;

  static AccionDispositivo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final tipo = j['tipo'] as String?;
    if (tipo == null || tipo.isEmpty) return null;
    return AccionDispositivo(
      tipo: tipo,
      datos: (j['datos'] as Map?)?.cast<String, dynamic>() ?? const {},
      resumen: (j['resumen'] as String?) ?? '',
      requiereConfirmacion: (j['requiere_confirmacion'] as bool?) ?? true,
    );
  }
}

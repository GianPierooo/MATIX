/// A qué se convierte el texto de una captura (OCR on-device).
///
/// La cámara inteligente es **una sola**: disparas, ML Kit extrae el
/// texto en el teléfono (la imagen NO sale) y Matix clasifica a cuál de
/// estos tres destinos pertenece para abrir el flujo de revisión que ya
/// existe. El usuario siempre puede corregir el tipo:
///
/// - [DestinoOcr.tareas]: una lista de pendientes → hoja de revisión (7-B).
/// - [DestinoOcr.eventos]: un horario o sílabo → revisión de eventos.
/// - [DestinoOcr.recibo]: una boleta/ticket → gasto en Finanzas (Finanzas-2).
/// - [DestinoOcr.apunte]: una nota/idea → apunte clasificado. Es el
///   catch-all: ante la duda, todo cae aquí (no se pierde nada).
enum DestinoOcr { tareas, apunte, eventos, recibo }

/// Mapea la etiqueta que devuelve el cerebro
/// (`POST /matix/clasificar-captura`) al destino de la app. Tolerante:
/// recorta y normaliza mayúsculas, y ante cualquier valor desconocido o
/// nulo cae a [DestinoOcr.apunte], el catch-all que no pierde nada.
DestinoOcr destinoDesdeTipo(String? tipo) {
  switch (tipo?.trim().toLowerCase()) {
    case 'tareas':
      return DestinoOcr.tareas;
    case 'eventos':
      return DestinoOcr.eventos;
    case 'recibo':
      return DestinoOcr.recibo;
    case 'apunte':
      return DestinoOcr.apunte;
    default:
      return DestinoOcr.apunte;
  }
}

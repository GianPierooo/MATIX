/// Aplanado del árbol de pantalla (Tier C.0 · percepción).
///
/// El servicio nativo de accesibilidad captura la ventana activa y la entrega
/// como un árbol JSON compacto:
///
///   {"ok": true, "app": "com.whatsapp", "arbol": {nodo}}
///   {"ok": false, "motivo": "sin_ventana"}
///
/// donde cada nodo es `{t: texto, d: descripción, id: viewId, c: clase,
/// h: [hijos]}` (solo con las claves que tienen contenido).
///
/// Estas funciones son PURAS (sin Flutter, sin canales): convierten ese árbol
/// a una representación de texto compacta que se manda al modelo como DATO.
/// Por eso se testean directo, sin device.
library;

/// Texto aplanado de la captura: una línea por nodo con texto o descripción,
/// indentado según la jerarquía (los contenedores sin texto no suman sangría,
/// para que quede legible). Devuelve '' si la captura no trae contenido.
String aplanarPantalla(Map<String, dynamic> captura, {int maxLineas = 400}) {
  if (captura['ok'] != true) return '';
  final arbol = captura['arbol'];
  if (arbol is! Map) return '';
  final lineas = <String>[];
  _recorrer(arbol, 0, lineas, maxLineas);
  return lineas.join('\n');
}

/// Paquete (app) de la captura, o '' si no vino.
String appDeCaptura(Map<String, dynamic> captura) =>
    (captura['app'] as String?)?.trim() ?? '';

void _recorrer(Map<dynamic, dynamic> nodo, int nivel, List<String> out, int max) {
  if (out.length >= max) return;

  final t = (nodo['t'] as String?)?.trim();
  final d = (nodo['d'] as String?)?.trim();

  final partes = <String>[];
  if (t != null && t.isNotEmpty) partes.add(t);
  // La descripción solo si aporta algo distinto del texto visible.
  if (d != null && d.isNotEmpty && d != t) partes.add('[$d]');

  var nivelHijos = nivel;
  if (partes.isNotEmpty) {
    out.add('${'  ' * nivel}${partes.join(' ')}');
    nivelHijos = nivel + 1;
  }

  final hijos = nodo['h'];
  if (hijos is List) {
    for (final hijo in hijos) {
      if (out.length >= max) break;
      if (hijo is Map) _recorrer(hijo, nivelHijos, out, max);
    }
  }
}

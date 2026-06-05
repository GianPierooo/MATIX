// Red de seguridad de la UI contra el markdown crudo.
//
// El system prompt ya le prohíbe al modelo emitir markdown (nada de asteriscos
// de negrita/itálica, ni almohadillas de título). Pero NO confiamos solo en eso:
// a un modelo chico (Haiku) a veces se le escapa un `**así**`. Esta función
// limpia TODA salida mostrada antes de pintarla, así el usuario nunca ve
// markdown crudo.
//
// Preserva intactos los enlaces markdown `[texto](url)` y las URLs sueltas: de
// esos se encarga `TextoConEnlaces` (los vuelve tocables). PURO y testeable.

// Enlace markdown completo `[txt](https://…)`.
final _reEnlaceMd = RegExp(r'\[[^\]]+\]\(https?://[^\s)]+\)');
// URL suelta.
final _reUrl = RegExp(r'https?://[^\s<>()\]]+');

// Encabezados `### …` y citas `> …` al inicio de línea.
final _reEncabezado = RegExp(r'^[ \t]{0,3}#{1,6}[ \t]+', multiLine: true);
final _reCita = RegExp(r'^[ \t]{0,3}>[ \t]?', multiLine: true);
// Viñeta con asterisco al inicio de línea → guion (el estándar del proyecto).
final _reVineta = RegExp(r'^([ \t]*)\*[ \t]+', multiLine: true);

// Énfasis: doble (negrita) antes que simple (itálica) para no romper anidados.
final _reNegrita = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
final _reNegritaBaja = RegExp(r'__(.+?)__', dotAll: true);
final _reTachado = RegExp(r'~~(.+?)~~', dotAll: true);
// Itálica con asterisco: exige no-palabra a los lados para no tocar `a*b` (mult).
final _reItalicaAst =
    RegExp(r'(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])', dotAll: true);
// Itálica con guion bajo: igual, para no tocar `snake_case`.
final _reItalicaBaja =
    RegExp(r'(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])', dotAll: true);
// Código en línea `así`.
final _reCodigo = RegExp(r'`([^`]+)`');

// Centinelas en la zona de uso privado de Unicode (U+E000/U+E001): envuelven el
// índice del token protegido sin chocar nunca con texto real.
final String _ini = String.fromCharCode(0xE000);
final String _fin = String.fromCharCode(0xE001);
final RegExp _reToken = RegExp('$_ini(\\d+)$_fin');

/// Quita el markdown de formato de [texto], dejándolo plano. Idempotente:
/// aplicarla dos veces da lo mismo. Si no hay marcas, devuelve el mismo texto.
String limpiarMarkdown(String texto) {
  if (texto.isEmpty) return texto;
  // Atajo barato: sin ningún carácter de marca no hay nada que limpiar.
  if (!texto.contains(RegExp(r'[*_`#~>]'))) return texto;

  final guardados = <String>[];
  var t = texto;

  // Protege enlaces y URLs (para no tocar sus `_`, `~`, etc.).
  String proteger(RegExp re) => t.replaceAllMapped(re, (m) {
        guardados.add(m[0]!);
        return '$_ini${guardados.length - 1}$_fin';
      });
  t = proteger(_reEnlaceMd);
  t = proteger(_reUrl);

  t = t.replaceAll(_reEncabezado, '');
  t = t.replaceAll(_reCita, '');
  t = t.replaceAllMapped(_reVineta, (m) => '${m[1]}- ');
  t = t.replaceAllMapped(_reNegrita, (m) => m[1]!);
  t = t.replaceAllMapped(_reNegritaBaja, (m) => m[1]!);
  t = t.replaceAllMapped(_reTachado, (m) => m[1]!);
  t = t.replaceAllMapped(_reItalicaAst, (m) => m[1]!);
  t = t.replaceAllMapped(_reItalicaBaja, (m) => m[1]!);
  t = t.replaceAllMapped(_reCodigo, (m) => m[1]!);
  // Pares sueltos que sobren (negrita sin cerrar, etc.).
  t = t.replaceAll('**', '').replaceAll('__', '');

  // Restaura lo protegido.
  t = t.replaceAllMapped(_reToken, (m) => guardados[int.parse(m[1]!)]);
  return t;
}

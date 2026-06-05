import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/markdown_plano.dart';
import '../../../../theme/matix_colors.dart';

/// Un trozo de texto: plano, o un enlace (cuando [url] no es nulo).
@immutable
class SegmentoTexto {
  const SegmentoTexto(this.texto, {this.url});
  final String texto;
  final String? url;

  bool get esEnlace => url != null;

  @override
  bool operator ==(Object other) =>
      other is SegmentoTexto && other.texto == texto && other.url == url;

  @override
  int get hashCode => Object.hash(texto, url);
}

// Enlace markdown `[texto](url)`.
final _reMarkdown = RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+)\)');
// URL suelta `https://…` (sin estar dentro de un markdown).
final _reUrl = RegExp(r'https?://[^\s<>()\]]+');
// Puntuación final que NO es parte de la URL (típico al final de frase).
const _colaPuntuacion = '.,;:!?)]}»';

/// Parte `texto` en segmentos planos y de enlace. Reconoce:
/// - Enlaces markdown: `[Binance](https://binance.com)` → muestra "Binance".
/// - URLs sueltas: `https://binance.com` → muestra la URL.
///
/// Función PURA (sin Flutter) para poder testearla. La puntuación final pegada
/// a una URL suelta se devuelve como texto plano, no como parte del enlace.
List<SegmentoTexto> parsearEnlaces(String texto) {
  final segmentos = <SegmentoTexto>[];
  var i = 0;
  while (i < texto.length) {
    final md = _reMarkdown.matchAsPrefix(texto, i);
    if (md != null) {
      segmentos.add(SegmentoTexto(md.group(1)!, url: md.group(2)));
      i = md.end;
      continue;
    }
    final url = _reUrl.matchAsPrefix(texto, i);
    if (url != null) {
      var u = url.group(0)!;
      var cola = '';
      while (u.isNotEmpty && _colaPuntuacion.contains(u[u.length - 1])) {
        cola = u[u.length - 1] + cola;
        u = u.substring(0, u.length - 1);
      }
      segmentos.add(SegmentoTexto(u, url: u));
      if (cola.isNotEmpty) _agregarPlano(segmentos, cola);
      i = url.end;
      continue;
    }
    // Carácter plano: lo acumulamos en el último segmento plano si existe.
    _agregarPlano(segmentos, texto[i]);
    i++;
  }
  return segmentos;
}

void _agregarPlano(List<SegmentoTexto> segs, String s) {
  if (segs.isNotEmpty && !segs.last.esEnlace) {
    segs[segs.length - 1] = SegmentoTexto(segs.last.texto + s);
  } else {
    segs.add(SegmentoTexto(s));
  }
}

/// Muestra texto haciendo TOCABLES los enlaces (markdown y URLs sueltas). Se usa
/// en las burbujas del chat para que las fuentes de `buscar_web` se puedan abrir.
/// Mantiene la selección de texto (SelectableText.rich).
class TextoConEnlaces extends StatefulWidget {
  const TextoConEnlaces(this.texto, {super.key, this.style});
  final String texto;
  final TextStyle? style;

  @override
  State<TextoConEnlaces> createState() => _TextoConEnlacesState();
}

class _TextoConEnlacesState extends State<TextoConEnlaces> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _abrir(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri); // fallback al modo por defecto
      }
    } catch (_) {
      // Abrir un enlace nunca debe romper el chat.
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final base = widget.style ?? const TextStyle();
    // Red de seguridad: limpiamos cualquier markdown crudo del modelo antes de
    // pintar (preserva los enlaces, que se vuelven tocables abajo).
    final segmentos = parsearEnlaces(limpiarMarkdown(widget.texto));
    final spans = <InlineSpan>[];
    for (final s in segmentos) {
      if (!s.esEnlace) {
        spans.add(TextSpan(text: s.texto));
        continue;
      }
      final rec = TapGestureRecognizer()..onTap = () => _abrir(s.url!);
      _recognizers.add(rec);
      spans.add(
        TextSpan(
          text: s.texto,
          recognizer: rec,
          style: const TextStyle(
            color: MatixColors.accent,
            decoration: TextDecoration.underline,
            decorationColor: MatixColors.accent,
          ),
        ),
      );
    }
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }
}

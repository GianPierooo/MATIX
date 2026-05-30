import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/captura_camara/domain/destino_ocr.dart';

/// Tests del mapeo etiqueta-del-cerebro → destino de la app
/// (`destinoDesdeTipo`). Es la pieza pura de la cámara inteligente: la
/// clasificación a cada tipo y el catch-all ante lo desconocido.

void main() {
  test('cada etiqueta válida mapea a su destino', () {
    expect(destinoDesdeTipo('tareas'), DestinoOcr.tareas);
    expect(destinoDesdeTipo('eventos'), DestinoOcr.eventos);
    expect(destinoDesdeTipo('recibo'), DestinoOcr.recibo);
    expect(destinoDesdeTipo('apunte'), DestinoOcr.apunte);
  });

  test('tolera espacios y mayúsculas', () {
    expect(destinoDesdeTipo('  Tareas '), DestinoOcr.tareas);
    expect(destinoDesdeTipo('EVENTOS'), DestinoOcr.eventos);
  });

  test('valor desconocido o nulo cae a apunte (catch-all)', () {
    expect(destinoDesdeTipo('basura'), DestinoOcr.apunte);
    expect(destinoDesdeTipo(''), DestinoOcr.apunte);
    expect(destinoDesdeTipo(null), DestinoOcr.apunte);
  });
}

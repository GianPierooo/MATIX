import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/matix_chat_repository.dart';
import 'package:matix/features/matix/presentation/widgets/opciones_interactivas.dart';

/// Opciones tocables: el bloque se parsea y, al tocar/enviar, manda la
/// respuesta correcta (selección única, múltiple y campo de texto).
void main() {
  group('BloqueOpciones.fromJson', () {
    test('selección única', () {
      final b = BloqueOpciones.fromJson({
        'pregunta': '¿Qué plazo?',
        'opciones': ['Corto', 'Medio', 'Largo'],
        'tipo': 'seleccion_unica',
      });
      expect(b.pregunta, '¿Qué plazo?');
      expect(b.opciones, ['Corto', 'Medio', 'Largo']);
      expect(b.tipo, 'seleccion_unica');
      expect(b.esTexto, isFalse);
      expect(b.esMultiple, isFalse);
    });

    test('texto sin opciones', () {
      final b = BloqueOpciones.fromJson({'pregunta': 'x', 'tipo': 'texto'});
      expect(b.esTexto, isTrue);
      expect(b.opciones, isEmpty);
    });

    test('permite_texto: default true y se respeta false', () {
      final porDefecto = BloqueOpciones.fromJson({
        'pregunta': '¿plazo?',
        'opciones': ['Corto', 'Largo'],
        'tipo': 'seleccion_unica',
      });
      expect(porDefecto.permiteTexto, isTrue); // regla de oro
      final apagado = BloqueOpciones.fromJson({
        'pregunta': '¿sí o no?',
        'opciones': ['Sí', 'No'],
        'tipo': 'seleccion_unica',
        'permite_texto': false,
      });
      expect(apagado.permiteTexto, isFalse);
    });
  });

  Future<void> pump(WidgetTester tester, BloqueOpciones b, List<String> out) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OpcionesInteractivas(
          bloque: b,
          enabled: true,
          onResponder: out.add,
        ),
      ),
    ));
  }

  testWidgets('selección única: tocar un chip manda esa opción', (tester) async {
    final out = <String>[];
    await pump(
      tester,
      const BloqueOpciones(
        pregunta: '¿Qué plazo?',
        opciones: ['Corto', 'Medio', 'Largo'],
        tipo: 'seleccion_unica',
      ),
      out,
    );
    await tester.tap(find.text('Medio'));
    await tester.pump();
    expect(out, ['Medio']);
  });

  testWidgets('selección múltiple: marcar dos + Enviar manda la lista',
      (tester) async {
    final out = <String>[];
    await pump(
      tester,
      const BloqueOpciones(
        pregunta: '¿Cuáles?',
        opciones: ['A', 'B', 'C'],
        tipo: 'seleccion_multiple',
      ),
      out,
    );
    // Marcar A y C (no se manda nada todavía).
    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.tap(find.text('C'));
    await tester.pump();
    expect(out, isEmpty);
    // Enviar manda la lista en el orden del bloque.
    await tester.tap(find.text('Enviar'));
    await tester.pump();
    expect(out, ['A, C']);
  });

  testWidgets('texto: escribir + enviar manda lo escrito', (tester) async {
    final out = <String>[];
    await pump(
      tester,
      const BloqueOpciones(pregunta: '¿Cómo?', opciones: [], tipo: 'texto'),
      out,
    );
    await tester.enterText(find.byType(TextField), 'mi respuesta');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(out, ['mi respuesta']);
  });

  testWidgets('chips con permite_texto muestran el cue de escribir', (tester) async {
    await pump(
      tester,
      const BloqueOpciones(
        pregunta: '¿Qué plazo?',
        opciones: ['Corto', 'Largo'],
        tipo: 'seleccion_unica',
      ),
      <String>[],
    );
    expect(find.textContaining('escribe tu respuesta'), findsOneWidget);
  });

  testWidgets('chips con permite_texto=false NO muestran el cue', (tester) async {
    await pump(
      tester,
      const BloqueOpciones(
        pregunta: '¿Sí o no?',
        opciones: ['Sí', 'No'],
        tipo: 'seleccion_unica',
        permiteTexto: false,
      ),
      <String>[],
    );
    expect(find.textContaining('escribe tu respuesta'), findsNothing);
  });
}

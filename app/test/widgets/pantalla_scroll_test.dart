import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/widgets/pantalla_scroll.dart';

/// Garantías del wrapper de scroll: que todo el contenido sea alcanzable
/// (scroll) y que se reserve colchón inferior (para no quedar tapado por la
/// barra de navegación).
void main() {
  List<Widget> muchos(String prefijo) =>
      [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('$prefijo-$i'))];

  testWidgets('PantallaScroll deja scrollear hasta el último ítem', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PantallaScroll(
        appBar: AppBar(title: const Text('t')),
        bajoNav: true,
        children: muchos('p'),
      ),
    ));
    // El último ítem no entra en pantalla al inicio…
    expect(find.text('p-39'), findsNothing);
    // …pero se alcanza scrolleando.
    await tester.scrollUntilVisible(find.text('p-39'), 300);
    expect(find.text('p-39'), findsOneWidget);
  });

  testWidgets('PantallaScroll reserva colchón inferior bajo la nav', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PantallaScroll(bajoNav: true, children: [Text('x')]),
    ));
    final lv = tester.widget<ListView>(find.byType(ListView));
    final pad = lv.padding as EdgeInsets;
    // Con bajoNav el colchón inferior es ≥ el guard (32 + safe area).
    expect(pad.bottom, greaterThanOrEqualTo(32));
  });

  testWidgets('PantallaScroll con formKey envuelve en Form', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: PantallaScroll(
        formKey: key,
        children: const [TextField()],
      ),
    ));
    expect(find.byType(Form), findsOneWidget);
  });

  testWidgets('HojaScroll deja scrollear contenido alto', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HojaScroll(children: muchos('h')),
      ),
    ));
    // El contenido vive en un scroll view (no se corta).
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // El último ítem es alcanzable scrolleando (sin excepción de overflow).
    await tester.scrollUntilVisible(find.text('h-39'), 300);
    expect(find.text('h-39'), findsOneWidget);
  });
}

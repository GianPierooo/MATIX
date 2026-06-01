import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/presentation/widgets/menu_adjuntar.dart';

/// El menú de adjuntar muestra las 5 opciones y devuelve la elegida.
void main() {
  Future<OpcionAdjuntar?> abrirYToca(WidgetTester tester, String label) async {
    // Superficie tamaño teléfono (el grid usa aspect ratio fijo; en la
    // superficie de test por defecto, 800px de ancho, las celdas se agrandan
    // y desbordan — en un teléfono real entra sobrado).
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    OpcionAdjuntar? elegido;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  elegido = await mostrarMenuAdjuntar(ctx);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    // Todas las opciones visibles.
    expect(find.text('Documento'), findsOneWidget);
    expect(find.text('Foto/Video'), findsOneWidget);
    expect(find.text('Cámara'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Contacto'), findsOneWidget);
    expect(find.text('Adjuntar'), findsOneWidget);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    return elegido;
  }

  testWidgets('muestra las 5 opciones y devuelve Documento', (tester) async {
    expect(await abrirYToca(tester, 'Documento'), OpcionAdjuntar.documento);
  });

  testWidgets('devuelve Contacto al tocarlo', (tester) async {
    expect(await abrirYToca(tester, 'Contacto'), OpcionAdjuntar.contacto);
  });

  testWidgets('devuelve Cámara al tocarla', (tester) async {
    expect(await abrirYToca(tester, 'Cámara'), OpcionAdjuntar.camara);
  });
}

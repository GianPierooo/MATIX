import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/captura_camara/presentation/resultado_ocr_screen.dart';

/// Test del override del tipo en la cámara inteligente: si Matix adivinó
/// mal, el selector "esto en realidad es → tareas/eventos/apunte" reabre
/// el flujo correcto. Lo comprobamos por el botón de acción, que cambia
/// según el destino — sin pegar al cerebro (no se llama a ningún flujo).

Future<void> _montar(WidgetTester tester, DestinoOcr destino) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: ResultadoOcrScreen(
          textoInicial: 'texto ya corregido',
          destino: destino,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('arranca con el tipo clasificado (tareas)', (tester) async {
    await _montar(tester, DestinoOcr.tareas);
    expect(find.text('Convertir en tareas'), findsOneWidget);
  });

  testWidgets('corregir a Eventos reabre el flujo de eventos',
      (tester) async {
    await _montar(tester, DestinoOcr.tareas);
    expect(find.text('Convertir en tareas'), findsOneWidget);

    await tester.tap(find.text('Eventos'));
    await tester.pumpAndSettle();

    expect(find.text('Convertir en eventos'), findsOneWidget);
    expect(find.text('Convertir en tareas'), findsNothing);
  });

  testWidgets('corregir a Apunte reabre el flujo de apunte', (tester) async {
    await _montar(tester, DestinoOcr.eventos);
    expect(find.text('Convertir en eventos'), findsOneWidget);

    await tester.tap(find.text('Apunte'));
    await tester.pumpAndSettle();

    expect(find.text('Guardar como apunte'), findsOneWidget);
    expect(find.text('Convertir en eventos'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matix/main.dart';

Widget _appBajoScope() => const ProviderScope(child: MatixApp());

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es', null);
  });

  testWidgets('La app arranca y muestra el bottom nav con 5 pestañas',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appBajoScope());

    // Los 5 labels del bottom nav (Inicio aparece también como
    // título de la pantalla activa por defecto, de ahí `findsWidgets`).
    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('Proyectos'), findsOneWidget);
    expect(find.text('Matix'), findsOneWidget);
    expect(find.text('Tareas'), findsOneWidget);
    expect(find.text('Universidad'), findsOneWidget);
  });

  testWidgets('Tocar Proyectos abre la pantalla real (AppBar + loading)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appBajoScope());
    await tester.tap(find.text('Proyectos'));
    await tester.pump();
    // El AppBar tiene el título y un botón de "nuevo proyecto" (Icons.add).
    expect(find.text('Proyectos'), findsWidgets);
    expect(find.byIcon(Icons.add), findsWidgets);
  });
}

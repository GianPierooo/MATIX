// Regresión del "no hay forma de crear una tarea a mano": el botón de
// crear vive en el AppBar (como en eventos y proyectos), NO en un FAB.
//
// La pantalla de Tareas vive en el HomeShell con `extendBody: true`, así
// que un FloatingActionButton queda tapado detrás de la barra de
// navegación elevada y se vuelve invisible/intocable. Este test fija que:
//   1. NO hay FAB en la pantalla de Tareas.
//   2. Hay un botón "Nueva tarea" en el AppBar que abre el formulario de
//      alta.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matix/features/tareas/domain/selectores.dart';
import 'package:matix/features/tareas/domain/tarea.dart';
import 'package:matix/features/tareas/presentation/tareas_list_screen.dart';
import 'package:matix/features/tareas/providers/tareas_providers.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('es', null));

  Widget bajoScope() => ProviderScope(
        overrides: [
          tareasProvider.overrideWith((ref) async => const <Tarea>[]),
          categoriasProvider.overrideWith((ref) async => const <CategoriaRef>[]),
          cursosProvider.overrideWith((ref) async => const <CursoRef>[]),
          proyectosProvider.overrideWith((ref) async => const <ProyectoRef>[]),
        ],
        child: const MaterialApp(home: TareasListScreen()),
      );

  testWidgets('la pantalla de Tareas no usa FAB (quedaría tapado por la nav)',
      (tester) async {
    await tester.pumpWidget(bajoScope());
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('el botón "Nueva tarea" del AppBar abre el formulario de alta',
      (tester) async {
    await tester.pumpWidget(bajoScope());
    await tester.pumpAndSettle();

    final boton = find.byTooltip('Nueva tarea');
    expect(boton, findsOneWidget);

    await tester.tap(boton);
    await tester.pumpAndSettle();

    // Se abrió el formulario de alta: su AppBar dice "Nueva tarea" y se
    // ve el campo de título arriba. (El botón "Crear tarea" vive al fondo
    // del ListView, fuera del viewport, por eso no lo verificamos acá.)
    expect(find.text('Nueva tarea'), findsWidgets);
    expect(find.text('Título'), findsOneWidget);
  });
}

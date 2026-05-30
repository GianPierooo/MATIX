// Regresión del scroll cortado (Push/Layout): el Calendario vive en el
// HomeShell con `extendBody: true`, así que sus listas internas deben
// reservar padding inferior (MatixLayout.bottomNavGuard) o los últimos
// ítems quedan tapados por la barra de navegación. El síntoma reportado:
// en la vista Semana no se podía bajar hasta el sábado/domingo.
//
// Este test verifica que la lista de la vista Semana aplica ese guard:
// su padding inferior es mucho mayor que el superior (8 px), prueba de
// que usa el guard y no el `vertical: 8` viejo que dejaba el contenido
// detrás de la nav.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matix/features/cursos/domain/curso.dart';
import 'package:matix/features/cursos/domain/sesion_clase.dart';
import 'package:matix/features/eventos/domain/evento.dart';
import 'package:matix/features/eventos/presentation/calendario_screen.dart';
import 'package:matix/features/eventos/providers/eventos_providers.dart';
import 'package:matix/features/universidad/providers/universidad_providers.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es', null);
  });

  testWidgets(
      'la lista de la vista Semana reserva el guard inferior (no queda '
      'tapada por la barra de navegación)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventosProvider.overrideWith((ref) async => const <Evento>[]),
          cursosListProvider.overrideWith((ref) async => const <Curso>[]),
          sesionesClaseProvider
              .overrideWith((ref) async => const <SesionClase>[]),
        ],
        child: MaterialApp(
          // Simulamos el inset que el shell inyecta por `extendBody`.
          home: MediaQuery(
            data: const MediaQueryData(
              viewPadding: EdgeInsets.only(bottom: 48),
              padding: EdgeInsets.only(bottom: 48),
            ),
            child: const CalendarioScreen(),
          ),
        ),
      ),
    );
    // Resuelve los FutureProviders.
    await tester.pumpAndSettle();

    // Cambiamos a la vista Semana.
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();

    final lista = tester.widget<ListView>(
      find.byKey(const Key('cal-semana-lista')),
    );
    final padding = lista.padding!.resolve(TextDirection.ltr);

    // El viejo código usaba `vertical: 8` (top == bottom == 8). El fix
    // mete el guard abajo: bottom muy por encima de 8.
    expect(padding.top, 8);
    expect(padding.bottom, greaterThan(8));
    // El guard es al menos la constante del FAB (32) aunque el inset no
    // se propague en el árbol de test.
    expect(padding.bottom, greaterThanOrEqualTo(32));
  });
}

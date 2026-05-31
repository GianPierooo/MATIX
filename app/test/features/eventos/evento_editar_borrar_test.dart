// Fija que el formulario de evento expone editar y borrar:
//   - En modo alta (sin evento): título "Nuevo evento" + botón "Crear
//     evento", sin botón de borrar.
//   - En modo edición (con evento): título "Editar evento", campos
//     precargados y botón de borrar (a la papelera).
//
// El flujo real: tocar un evento en el Calendario abre esta pantalla con
// el evento cargado (editar), y desde acá se borra. No metemos
// excepciones por ocurrencia: editar/borrar es sobre la serie/evento.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matix/features/eventos/domain/evento.dart';
import 'package:matix/features/eventos/presentation/nuevo_evento_screen.dart';
import 'package:matix/features/universidad/providers/universidad_providers.dart';

Evento _evento() => Evento.fromJson({
      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'titulo': 'Reunión de tesis',
      'inicia_en': '2026-06-15T13:00:00Z',
      'termina_en': '2026-06-15T15:00:00Z',
      'todo_el_dia': false,
      'creado_en': '2026-06-01T00:00:00Z',
      'actualizado_en': '2026-06-01T00:00:00Z',
    });

Widget _bajoScope(Widget child) => ProviderScope(
      overrides: [
        cursosListProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  setUpAll(() async => initializeDateFormatting('es', null));

  testWidgets('alta: título "Nuevo evento", crear, sin borrar', (tester) async {
    await tester.pumpWidget(_bajoScope(const NuevoEventoScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo evento'), findsOneWidget);
    // En alta no hay botón de borrar.
    expect(find.byTooltip('Borrar'), findsNothing);
  });

  testWidgets('edición: título "Editar evento", datos cargados y borrar',
      (tester) async {
    await tester.pumpWidget(_bajoScope(NuevoEventoScreen(evento: _evento())));
    await tester.pumpAndSettle();

    expect(find.text('Editar evento'), findsOneWidget);
    // El título del evento llega precargado en el campo (visible arriba).
    expect(find.text('Reunión de tesis'), findsOneWidget);
    // Y hay un botón de borrar (a la papelera) en el AppBar.
    expect(find.byTooltip('Borrar'), findsOneWidget);
  });
}

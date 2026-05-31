// Navegación desde el chat (Matix gestiona la app): el cerebro emite
// `navegacion` en la respuesta del chat, el repo la traduce a ChatTurno
// y la capa de UI la mapea a una SeccionMatix. Acá fijamos:
//   - el mapeo string → SeccionMatix (todas las secciones + desconocida)
//   - que ChatTurno lee `navegacion` del JSON del cerebro.

import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/matix_chat_repository.dart';
import 'package:matix/features/matix/providers/navegacion_matix_provider.dart';

void main() {
  group('seccionMatixDeString', () {
    test('mapea cada sección conocida', () {
      expect(seccionMatixDeString('inicio'), SeccionMatix.inicio);
      expect(seccionMatixDeString('tareas'), SeccionMatix.tareas);
      expect(seccionMatixDeString('calendario'), SeccionMatix.calendario);
      expect(seccionMatixDeString('proyectos'), SeccionMatix.proyectos);
      expect(seccionMatixDeString('universidad'), SeccionMatix.universidad);
      expect(seccionMatixDeString('finanzas'), SeccionMatix.finanzas);
      expect(seccionMatixDeString('apuntes'), SeccionMatix.apuntes);
      expect(seccionMatixDeString('ajustes'), SeccionMatix.ajustes);
    });

    test('sección desconocida o null → null (no rompe)', () {
      expect(seccionMatixDeString('marte'), isNull);
      expect(seccionMatixDeString(null), isNull);
      expect(seccionMatixDeString(''), isNull);
    });
  });

  group('ChatTurno', () {
    test('navegacion es null cuando no hay (por defecto)', () {
      const t = ChatTurno(
        respuesta: 'hola',
        toolsUsadas: [],
        tablasCambiadas: [],
      );
      expect(t.navegacion, isNull);
      expect(seccionMatixDeString(t.navegacion), isNull);
    });

    test('navegacion presente se traduce a la sección', () {
      const t = ChatTurno(
        respuesta: 'Te llevo a Universidad',
        toolsUsadas: ['navegar'],
        tablasCambiadas: [],
        navegacion: 'universidad',
      );
      expect(seccionMatixDeString(t.navegacion), SeccionMatix.universidad);
    });
  });
}

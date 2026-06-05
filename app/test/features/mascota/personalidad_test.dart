import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/mascota/domain/personalidad.dart';

void main() {
  group('franjaDe', () {
    test('mapea la hora a la franja', () {
      expect(franjaDe(7), FranjaDia.manana);
      expect(franjaDe(13), FranjaDia.tarde);
      expect(franjaDe(21), FranjaDia.noche);
    });
  });

  group('saludo', () {
    test('da texto cálido con opciones y sin asteriscos', () {
      final m = saludo(FranjaDia.tarde, const ContextoMascota(tareasHoy: 3));
      expect(m.tipo, TipoMascota.saludo);
      expect(m.texto, isNotEmpty);
      expect(m.texto, contains('3')); // teje el contexto
      expect(m.texto.contains('*'), isFalse);
      expect(m.opciones, contains('Hablemos'));
    });
    test('menciona lo vencido sin culpar', () {
      final m = saludo(FranjaDia.manana, const ContextoMascota(vencidas: 2));
      expect(m.texto, contains('2'));
      expect(m.texto.toLowerCase(), isNot(contains('deberías')));
    });
    test('día sin pendientes: tono libre, no presión', () {
      final m = saludo(FranjaDia.tarde, ContextoMascota.vacio);
      expect(m.texto, isNotEmpty);
      expect(m.texto.contains('*'), isFalse);
    });
  });

  group('elegirAparicion', () {
    test('felicita si hubo avance y nada vencido', () {
      expect(
        elegirAparicion(const ContextoMascota(hechasHoy: 2)),
        TipoMascota.felicitacion,
      );
    });
    test('empuja suave si hay vencidas o proyecto en riesgo', () {
      expect(
        elegirAparicion(const ContextoMascota(vencidas: 1)),
        TipoMascota.empujoncito,
      );
      expect(
        elegirAparicion(const ContextoMascota(proyectosEnRiesgo: 1)),
        TipoMascota.empujoncito,
      );
    });
    test('sin señales: alterna aliento/comentario por paridad', () {
      expect(elegirAparicion(ContextoMascota.vacio, semilla: 2),
          TipoMascota.aliento);
      expect(elegirAparicion(ContextoMascota.vacio, semilla: 3),
          TipoMascota.comentario);
    });
  });

  group('aparicion y despedida', () {
    test('aparición trae texto y opciones, sin asteriscos', () {
      for (final t in [
        TipoMascota.aliento,
        TipoMascota.comentario,
        TipoMascota.felicitacion,
        TipoMascota.empujoncito,
      ]) {
        final m = aparicion(t, const ContextoMascota(hechasHoy: 3));
        expect(m.texto, isNotEmpty, reason: '$t');
        expect(m.texto.contains('*'), isFalse, reason: '$t');
        expect(m.opciones, isNotEmpty, reason: '$t');
      }
    });
    test('despedida corta, cálida y sin asteriscos', () {
      final m = despedida(FranjaDia.noche);
      expect(m.tipo, TipoMascota.despedida);
      expect(m.texto, isNotEmpty);
      expect(m.texto.contains('*'), isFalse);
    });
    test('determinista por semilla', () {
      final a = aparicion(TipoMascota.aliento, ContextoMascota.vacio, semilla: 5);
      final b = aparicion(TipoMascota.aliento, ContextoMascota.vacio, semilla: 5);
      expect(a.texto, b.texto);
    });
  });

  group('franjaPersonaDe (modo persona alineado a anclas, no al silencio)', () {
    test('antes de despertar → dormido', () {
      expect(franjaPersonaDe(3, despertar: 7, dormir: 23),
          FranjaPersona.dormido);
    });

    test('7:42 con despertar=7 → mañana (el bug del usuario)', () {
      // Antes salía "Modo noche" porque silencio terminaba a las 8;
      // ahora se alinea al ancla: despertar=7 → ya es mañana.
      expect(franjaPersonaDe(7, despertar: 7, dormir: 23),
          FranjaPersona.manana);
    });

    test('mañana hasta el mediodía', () {
      expect(franjaPersonaDe(10, despertar: 7, dormir: 23),
          FranjaPersona.manana);
    });

    test('tarde entre el mediodía y las 2h previas a dormir', () {
      expect(franjaPersonaDe(15, despertar: 7, dormir: 23),
          FranjaPersona.tarde);
      expect(franjaPersonaDe(20, despertar: 7, dormir: 23),
          FranjaPersona.tarde);
    });

    test('últimas 2h antes de dormir → noche (cierre del día)', () {
      expect(franjaPersonaDe(21, despertar: 7, dormir: 23),
          FranjaPersona.noche);
      expect(franjaPersonaDe(22, despertar: 7, dormir: 23),
          FranjaPersona.noche);
    });

    test('a la hora de dormir o después → dormido', () {
      expect(franjaPersonaDe(23, despertar: 7, dormir: 23),
          FranjaPersona.dormido);
      expect(franjaPersonaDe(2, despertar: 7, dormir: 23),
          FranjaPersona.dormido);
    });

    test('anclas raras (despertar>=dormir) no encierran al usuario', () {
      // Cae a una franja despierta razonable en vez de "dormido todo el día".
      final p = franjaPersonaDe(10, despertar: 23, dormir: 7);
      expect(p, isNot(FranjaPersona.dormido));
    });

    test('franjaDiaDePersona traduce a la franja del copy del saludo', () {
      expect(franjaDiaDePersona(FranjaPersona.manana), FranjaDia.manana);
      expect(franjaDiaDePersona(FranjaPersona.tarde), FranjaDia.tarde);
      expect(franjaDiaDePersona(FranjaPersona.noche), FranjaDia.noche);
      expect(franjaDiaDePersona(FranjaPersona.dormido), FranjaDia.noche);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:matix/core/notif_id.dart';
import 'package:matix/features/eventos/domain/recurrencia.dart';

void main() {
  group('ReglaRecurrencia · serialización', () {
    test('toJson de semanal manda solo lo que aplica', () {
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.semanal,
        diasSemana: {3, 1},
        fin: FinRecurrencia.hasta,
        hasta: null,
      );
      // hasta=null aunque fin=hasta → la columna va null (la valida la UI).
      final json = ReglaRecurrencia(
        frecuencia: regla.frecuencia,
        diasSemana: regla.diasSemana,
        fin: FinRecurrencia.hasta,
        hasta: DateTime(2026, 7, 15),
      ).toJson();
      expect(json['recurrencia_freq'], 'semanal');
      expect(json['recurrencia_dias_semana'], [1, 3]); // ordenados
      expect(json['recurrencia_fin_tipo'], 'hasta');
      expect(json['recurrencia_hasta'], '2026-07-15');
      expect(json['recurrencia_conteo'], isNull);
    });

    test('toJson de diaria por conteo no manda días ni hasta', () {
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.diaria,
        fin: FinRecurrencia.conteo,
        conteo: 5,
      );
      final json = regla.toJson();
      expect(json['recurrencia_freq'], 'diaria');
      expect(json['recurrencia_dias_semana'], isNull);
      expect(json['recurrencia_fin_tipo'], 'conteo');
      expect(json['recurrencia_conteo'], 5);
      expect(json['recurrencia_hasta'], isNull);
    });

    test('jsonNulo limpia las 5 columnas', () {
      final json = ReglaRecurrencia.jsonNulo();
      expect(json['recurrencia_freq'], isNull);
      expect(json['recurrencia_dias_semana'], isNull);
      expect(json['recurrencia_fin_tipo'], isNull);
      expect(json['recurrencia_hasta'], isNull);
      expect(json['recurrencia_conteo'], isNull);
    });

    test('maybeFromEventoJson devuelve null sin recurrencia', () {
      expect(
        ReglaRecurrencia.maybeFromEventoJson({'recurrencia_freq': null}),
        isNull,
      );
      expect(ReglaRecurrencia.maybeFromEventoJson({}), isNull);
    });

    test('maybeFromEventoJson reconstruye semanal con días y fin', () {
      final regla = ReglaRecurrencia.maybeFromEventoJson({
        'recurrencia_freq': 'semanal',
        'recurrencia_dias_semana': [1, 3],
        'recurrencia_fin_tipo': 'hasta',
        'recurrencia_hasta': '2026-07-15',
      });
      expect(regla, isNotNull);
      expect(regla!.frecuencia, FrecuenciaRecurrencia.semanal);
      expect(regla.diasSemana, {1, 3});
      expect(regla.fin, FinRecurrencia.hasta);
      expect(regla.hasta, DateTime(2026, 7, 15));
    });
  });

  group('ocurrenciasEntre · diaria', () {
    final inicio = DateTime(2026, 6, 15, 10, 0); // lunes

    test('expande el rango visible inclusive', () {
      const regla = ReglaRecurrencia(frecuencia: FrecuenciaRecurrencia.diaria);
      final occ = ocurrenciasEntre(
        regla: regla,
        inicioSerie: inicio,
        desde: DateTime(2026, 6, 15),
        hasta: DateTime(2026, 6, 20, 23, 59, 59),
      );
      expect(occ, [
        DateTime(2026, 6, 15, 10, 0),
        DateTime(2026, 6, 16, 10, 0),
        DateTime(2026, 6, 17, 10, 0),
        DateTime(2026, 6, 18, 10, 0),
        DateTime(2026, 6, 19, 10, 0),
        DateTime(2026, 6, 20, 10, 0),
      ]);
    });

    test('fin por conteo corta tras N ocurrencias', () {
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.diaria,
        fin: FinRecurrencia.conteo,
        conteo: 3,
      );
      final occ = ocurrenciasEntre(
        regla: regla,
        inicioSerie: inicio,
        desde: DateTime(2026, 6, 1),
        hasta: DateTime(2026, 12, 31),
      );
      expect(occ.length, 3);
      expect(occ.last, DateTime(2026, 6, 17, 10, 0));
    });

    test('el conteo cuenta desde el ancla, no desde `desde`', () {
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.diaria,
        fin: FinRecurrencia.conteo,
        conteo: 5,
      );
      // 5 ocurrencias desde el ancla: 15,16,17,18,19. En el rango pedido
      // (17–30) solo entran las 3 últimas.
      final occ = ocurrenciasEntre(
        regla: regla,
        inicioSerie: inicio,
        desde: DateTime(2026, 6, 17),
        hasta: DateTime(2026, 6, 30),
      );
      expect(occ, [
        DateTime(2026, 6, 17, 10, 0),
        DateTime(2026, 6, 18, 10, 0),
        DateTime(2026, 6, 19, 10, 0),
      ]);
    });

    test('fin por fecha es inclusivo', () {
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.diaria,
        fin: FinRecurrencia.hasta,
      );
      final occ = ocurrenciasEntre(
        regla: ReglaRecurrencia(
          frecuencia: regla.frecuencia,
          fin: FinRecurrencia.hasta,
          hasta: DateTime(2026, 6, 18),
        ),
        inicioSerie: inicio,
        desde: DateTime(2026, 6, 1),
        hasta: DateTime(2026, 12, 31),
      );
      expect(occ.length, 4);
      expect(occ.last, DateTime(2026, 6, 18, 10, 0));
    });
  });

  group('ocurrenciasEntre · semanal', () {
    test('lunes y miércoles en dos semanas', () {
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.semanal,
        diasSemana: {1, 3},
      );
      final occ = ocurrenciasEntre(
        regla: regla,
        inicioSerie: DateTime(2026, 6, 15, 9, 0), // lunes
        desde: DateTime(2026, 6, 15),
        hasta: DateTime(2026, 6, 28, 23, 59, 59),
      );
      expect(occ, [
        DateTime(2026, 6, 15, 9, 0),
        DateTime(2026, 6, 17, 9, 0),
        DateTime(2026, 6, 22, 9, 0),
        DateTime(2026, 6, 24, 9, 0),
      ]);
    });

    test('no emite días anteriores al ancla en su misma semana', () {
      // Ancla miércoles 17; el lunes 15 de esa semana NO cuenta.
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.semanal,
        diasSemana: {1, 3},
      );
      final occ = ocurrenciasEntre(
        regla: regla,
        inicioSerie: DateTime(2026, 6, 17, 8, 0), // miércoles
        desde: DateTime(2026, 6, 15),
        hasta: DateTime(2026, 6, 24, 23, 59, 59),
      );
      expect(occ.first, DateTime(2026, 6, 17, 8, 0));
      expect(occ, [
        DateTime(2026, 6, 17, 8, 0),
        DateTime(2026, 6, 22, 8, 0),
        DateTime(2026, 6, 24, 8, 0),
      ]);
    });

    test('cada día de semana (L–V) salta sábado y domingo', () {
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.semanal,
        diasSemana: {1, 2, 3, 4, 5},
      );
      final occ = ocurrenciasEntre(
        regla: regla,
        inicioSerie: DateTime(2026, 6, 15, 7, 30), // lunes
        desde: DateTime(2026, 6, 15),
        hasta: DateTime(2026, 6, 21, 23, 59, 59), // domingo
      );
      // L,M,X,J,V de esa semana = 15..19; sáb 20 y dom 21 fuera.
      expect(occ.length, 5);
      expect(occ.first, DateTime(2026, 6, 15, 7, 30));
      expect(occ.last, DateTime(2026, 6, 19, 7, 30));
    });
  });

  group('ocurrenciasEntre · mensual', () {
    test('salta los meses que no tienen el día de inicio (31)', () {
      const regla = ReglaRecurrencia(frecuencia: FrecuenciaRecurrencia.mensual);
      final occ = ocurrenciasEntre(
        regla: regla,
        inicioSerie: DateTime(2026, 1, 31, 10, 0),
        desde: DateTime(2026, 1, 1),
        hasta: DateTime(2026, 6, 30, 23, 59, 59),
      );
      // Ene31, (Feb no), Mar31, (Abr no), May31, (Jun no).
      expect(occ, [
        DateTime(2026, 1, 31, 10, 0),
        DateTime(2026, 3, 31, 10, 0),
        DateTime(2026, 5, 31, 10, 0),
      ]);
    });
  });

  group('ocurrenciasEnDia / eventoOcurreEnDia', () {
    const regla = ReglaRecurrencia(
      frecuencia: FrecuenciaRecurrencia.semanal,
      diasSemana: {1, 3},
    );
    final inicio = DateTime(2026, 6, 15, 9, 0); // lunes

    test('un día con ocurrencia devuelve esa hora', () {
      final occ = ocurrenciasEnDia(
        regla: regla,
        inicioSerie: inicio,
        dia: DateTime(2026, 6, 24, 15, 0), // miércoles, hora irrelevante
      );
      expect(occ, [DateTime(2026, 6, 24, 9, 0)]);
      expect(
        eventoOcurreEnDia(regla: regla, inicioSerie: inicio, dia: DateTime(2026, 6, 24)),
        isTrue,
      );
    });

    test('un día sin ocurrencia da lista vacía', () {
      // Martes 23 no está en {lun, mié}.
      expect(
        ocurrenciasEnDia(regla: regla, inicioSerie: inicio, dia: DateTime(2026, 6, 23)),
        isEmpty,
      );
      expect(
        eventoOcurreEnDia(regla: regla, inicioSerie: inicio, dia: DateTime(2026, 6, 23)),
        isFalse,
      );
    });
  });

  group('recordatoriosVentana', () {
    const uuid = '11111111-2222-3333-4444-555555555555';

    test('evento único futuro → un recordatorio con id base', () {
      final rs = recordatoriosVentana(
        eventoId: uuid,
        regla: null,
        inicioSerie: DateTime(2026, 6, 15, 10, 0),
        offsetMin: 10,
        ahora: DateTime(2026, 6, 15, 8, 0),
      );
      expect(rs.length, 1);
      expect(rs.single.cuando, DateTime(2026, 6, 15, 9, 50));
      expect(rs.single.notifId, notifIdDe(uuid));
    });

    test('evento único ya pasado → vacío', () {
      final rs = recordatoriosVentana(
        eventoId: uuid,
        regla: null,
        inicioSerie: DateTime(2026, 6, 15, 7, 0),
        offsetMin: 10,
        ahora: DateTime(2026, 6, 15, 8, 0),
      );
      expect(rs, isEmpty);
    });

    test('sin offset → vacío', () {
      final rs = recordatoriosVentana(
        eventoId: uuid,
        regla: const ReglaRecurrencia(frecuencia: FrecuenciaRecurrencia.diaria),
        inicioSerie: DateTime(2026, 6, 15, 10, 0),
        offsetMin: null,
        ahora: DateTime(2026, 6, 15, 8, 0),
      );
      expect(rs, isEmpty);
    });

    test('serie diaria agenda una noti por ocurrencia en la ventana', () {
      final rs = recordatoriosVentana(
        eventoId: uuid,
        regla: const ReglaRecurrencia(frecuencia: FrecuenciaRecurrencia.diaria),
        inicioSerie: DateTime(2026, 6, 15, 10, 0),
        offsetMin: 60,
        ahora: DateTime(2026, 6, 15, 8, 0),
        ventanaDias: 3,
      );
      // Ocurrencias 15,16,17 (10:00); la del 18 cae fuera de la ventana.
      expect(rs.length, 3);
      expect(rs.map((r) => r.cuando), [
        DateTime(2026, 6, 15, 9, 0),
        DateTime(2026, 6, 16, 9, 0),
        DateTime(2026, 6, 17, 9, 0),
      ]);
      // Ids distintos por día (no colisionan como con notifIdDe).
      expect(rs.map((r) => r.notifId).toSet().length, 3);
      expect(rs[0].notifId, notifIdDeOcurrencia(uuid, DateTime(2026, 6, 15)));
    });

    test('excluye ocurrencias cuyo recordatorio ya pasó', () {
      final rs = recordatoriosVentana(
        eventoId: uuid,
        regla: const ReglaRecurrencia(frecuencia: FrecuenciaRecurrencia.diaria),
        inicioSerie: DateTime(2026, 6, 15, 10, 0),
        offsetMin: 60, // recordatorio 09:00 cada día
        ahora: DateTime(2026, 6, 15, 9, 30), // el del día 15 ya pasó
        ventanaDias: 3,
      );
      // 15 excluido (09:00 < 09:30); quedan 16 y 17.
      expect(rs.map((r) => r.cuando), [
        DateTime(2026, 6, 16, 9, 0),
        DateTime(2026, 6, 17, 9, 0),
      ]);
    });

    test('serie ya terminada → vacío', () {
      final rs = recordatoriosVentana(
        eventoId: uuid,
        regla: ReglaRecurrencia(
          frecuencia: FrecuenciaRecurrencia.diaria,
          fin: FinRecurrencia.hasta,
          hasta: DateTime(2026, 6, 10),
        ),
        inicioSerie: DateTime(2026, 6, 1, 10, 0),
        offsetMin: 10,
        ahora: DateTime(2026, 6, 15, 8, 0),
        ventanaDias: 30,
      );
      expect(rs, isEmpty);
    });
  });

  group('idsCancelacionVentana', () {
    const uuid = '11111111-2222-3333-4444-555555555555';
    final ahora = DateTime(2026, 6, 15, 8, 0);

    test('incluye el id base y un id por día de la ventana', () {
      final ids = idsCancelacionVentana(
        eventoId: uuid,
        ahora: ahora,
        ventanaDias: 30,
      );
      expect(ids, contains(notifIdDe(uuid)));
      expect(ids, contains(notifIdDeOcurrencia(uuid, DateTime(2026, 6, 15))));
      expect(ids, contains(notifIdDeOcurrencia(uuid, DateTime(2026, 7, 15))));
    });

    test('cancela todo lo que la ventana pudo agendar (simetría)', () {
      const regla = ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.semanal,
        diasSemana: {1, 2, 3, 4, 5},
      );
      final agendados = recordatoriosVentana(
        eventoId: uuid,
        regla: regla,
        inicioSerie: DateTime(2026, 6, 15, 7, 0),
        offsetMin: 30,
        ahora: ahora,
        ventanaDias: 30,
      ).map((r) => r.notifId).toSet();
      final cancelables = idsCancelacionVentana(
        eventoId: uuid,
        ahora: ahora,
        ventanaDias: 30,
      );
      expect(agendados, isNotEmpty);
      // Cada id agendado debe estar en el set que se cancela al editar/borrar.
      expect(agendados.difference(cancelables), isEmpty);
    });
  });
}

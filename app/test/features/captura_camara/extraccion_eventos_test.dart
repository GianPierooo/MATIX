import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matix/features/captura_camara/application/extraccion_eventos_controller.dart';
import 'package:matix/features/captura_camara/data/extraccion_eventos_repository.dart';
import 'package:matix/features/captura_camara/domain/evento_propuesto.dart';
import 'package:matix/features/eventos/data/eventos_repository.dart';
import 'package:matix/features/eventos/domain/evento.dart';
import 'package:matix/features/eventos/domain/recurrencia.dart';
import 'package:matix/features/eventos/providers/eventos_providers.dart';

/// Tests del flujo sílabo → eventos: parseo recurrentes vs únicos +
/// fechas/horas, y que aceptar cree los eventos correctos (recurrentes
/// con regla semanal, únicos sin regla).

class _FakeExtraccion implements ExtraccionEventosRepository {
  _FakeExtraccion(this.resultado);
  final List<EventoPropuesto> resultado;
  @override
  Future<List<EventoPropuesto>> extraer(String texto) async => resultado;
}

class _FakeEventos implements EventosRepository {
  final List<Map<String, dynamic>> creados = [];

  @override
  Future<Evento> crear({
    required String titulo,
    String? descripcion,
    required DateTime iniciaEn,
    DateTime? terminaEn,
    bool todoElDia = false,
    String? ubicacion,
    String? cursoId,
    String? proyectoId,
    String? color,
    int? recordatorioOffsetMin,
    ReglaRecurrencia? regla,
  }) async {
    creados.add({
      'titulo': titulo,
      'iniciaEn': iniciaEn,
      'terminaEn': terminaEn,
      'todoElDia': todoElDia,
      'cursoId': cursoId,
      'color': color,
      'regla': regla,
    });
    return Evento(
      id: 'e${creados.length}',
      titulo: titulo,
      iniciaEn: iniciaEn,
      creadoEn: DateTime(2026, 1, 1),
      actualizadoEn: DateTime(2026, 1, 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('parseo y helpers de dominio', () {
    test('fromCerebro: recurrente con días y horas', () {
      final p = EventoPropuesto.fromCerebro({
        'tipo': 'recurrente',
        'titulo': '  Cálculo III  ',
        'dias_semana': [1, 3],
        'hora_inicio': '10:00',
        'hora_fin': '12:00',
      });
      expect(p.esRecurrente, isTrue);
      expect(p.titulo, 'Cálculo III');
      expect(p.diasSemana, {1, 3});
      expect(p.horaInicio, '10:00');
    });

    test('fromCerebro: único con fecha', () {
      final p = EventoPropuesto.fromCerebro({
        'tipo': 'unico',
        'titulo': 'Parcial',
        'fecha': '2026-04-15',
        'hora_inicio': '08:00',
      });
      expect(p.esRecurrente, isFalse);
      expect(p.fecha, DateTime(2026, 4, 15));
    });

    test('parametrosDe: recurrente → regla semanal + ancla en un día válido',
        () {
      const p = EventoPropuesto(
        tipo: TipoEventoPropuesto.recurrente,
        titulo: 'Clase',
        diasSemana: {1, 3}, // lunes y miércoles
        horaInicio: '10:00',
        horaFin: '12:00',
      );
      // Un domingo (2026-06-07 es domingo): el ancla cae el lunes 08.
      final par = parametrosDe(p, DateTime(2026, 6, 7, 9));
      expect(par.regla, isNotNull);
      expect(par.regla!.frecuencia, FrecuenciaRecurrencia.semanal);
      expect(par.regla!.diasSemana, {1, 3});
      expect({1, 3}.contains(par.iniciaEn.weekday), isTrue);
      expect(par.iniciaEn.hour, 10);
      expect(par.terminaEn!.hour, 12);
      expect(par.todoElDia, isFalse);
    });

    test('parametrosDe: único con hora → sin regla, fecha+hora exactas', () {
      const p = EventoPropuesto(
        tipo: TipoEventoPropuesto.unico,
        titulo: 'Parcial',
        horaInicio: '08:30',
      );
      final par = parametrosDe(
        p.copyWith(fecha: DateTime(2026, 4, 15)),
        DateTime(2026, 1, 1),
      );
      expect(par.regla, isNull);
      expect(par.iniciaEn, DateTime(2026, 4, 15, 8, 30));
      expect(par.todoElDia, isFalse);
    });

    test('parametrosDe: único sin hora → todo el día', () {
      const p = EventoPropuesto(
          tipo: TipoEventoPropuesto.unico, titulo: 'Feriado');
      final par = parametrosDe(
        p.copyWith(fecha: DateTime(2026, 4, 15)),
        DateTime(2026, 1, 1),
      );
      expect(par.todoElDia, isTrue);
      expect(par.iniciaEn, DateTime(2026, 4, 15));
    });
  });

  group('controller: aceptar crea los eventos correctos', () {
    test('recurrente con regla, único sin regla', () async {
      final fakeEventos = _FakeEventos();
      final c = ProviderContainer(overrides: [
        extraccionEventosRepositoryProvider.overrideWithValue(
          _FakeExtraccion([
            const EventoPropuesto(
              tipo: TipoEventoPropuesto.recurrente,
              titulo: 'Cálculo',
              diasSemana: {2},
              horaInicio: '09:00',
            ),
            EventoPropuesto(
              tipo: TipoEventoPropuesto.unico,
              titulo: 'Parcial',
              fecha: DateTime(2026, 4, 15),
              horaInicio: '08:00',
            ),
          ]),
        ),
        eventosRepositoryProvider.overrideWithValue(fakeEventos),
      ]);
      addTearDown(c.dispose);

      final ctrl = c.read(extraccionEventosControllerProvider.notifier);
      await ctrl.interpretar('texto del sílabo');
      expect(c.read(extraccionEventosControllerProvider).fase,
          FaseEventos.revision);
      expect(c.read(extraccionEventosControllerProvider).propuestas, hasLength(2));

      await ctrl.crear();

      expect(c.read(extraccionEventosControllerProvider).fase,
          FaseEventos.creado);
      expect(fakeEventos.creados, hasLength(2));
      // El recurrente lleva regla semanal; el único, sin regla.
      final rec = fakeEventos.creados.firstWhere((e) => e['titulo'] == 'Cálculo');
      final uni = fakeEventos.creados.firstWhere((e) => e['titulo'] == 'Parcial');
      expect(rec['regla'], isA<ReglaRecurrencia>());
      expect(uni['regla'], isNull);
      expect((uni['iniciaEn'] as DateTime), DateTime(2026, 4, 15, 8, 0));
    });

    test('texto vacío → error sin llamar al cerebro', () async {
      final c = ProviderContainer(overrides: [
        extraccionEventosRepositoryProvider
            .overrideWithValue(_FakeExtraccion(const [])),
      ]);
      addTearDown(c.dispose);
      await c.read(extraccionEventosControllerProvider.notifier).interpretar('  ');
      expect(c.read(extraccionEventosControllerProvider).fase,
          FaseEventos.error);
    });
  });
}

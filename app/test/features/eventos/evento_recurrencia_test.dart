import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/eventos/domain/evento.dart';
import 'package:matix/features/eventos/domain/recurrencia.dart';

Map<String, dynamic> _baseJson(Map<String, dynamic> extra) => {
      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'titulo': 'Clase de Cálculo',
      'inicia_en': '2026-06-15T13:00:00Z', // anclaje en UTC
      'termina_en': '2026-06-15T15:00:00Z',
      'todo_el_dia': false,
      'creado_en': '2026-06-01T00:00:00Z',
      'actualizado_en': '2026-06-01T00:00:00Z',
      ...extra,
    };

void main() {
  test('fromJson sin columnas de recurrencia → evento único', () {
    final e = Evento.fromJson(_baseJson({}));
    expect(e.regla, isNull);
    expect(e.esRecurrente, isFalse);
  });

  test('fromJson reconstruye la regla y marca esRecurrente', () {
    final e = Evento.fromJson(_baseJson({
      'recurrencia_freq': 'semanal',
      'recurrencia_dias_semana': [1, 3],
      'recurrencia_fin_tipo': 'conteo',
      'recurrencia_conteo': 8,
    }));
    expect(e.esRecurrente, isTrue);
    expect(e.regla!.frecuencia, FrecuenciaRecurrencia.semanal);
    expect(e.regla!.diasSemana, {1, 3});
    expect(e.regla!.fin, FinRecurrencia.conteo);
    expect(e.regla!.conteo, 8);
  });

  test('ocurreEn de una serie diaria es true en días futuros del rango', () {
    final e = Evento.fromJson(_baseJson({
      'recurrencia_freq': 'diaria',
    }));
    // Comparación por día local del ancla.
    final ancla = e.iniciaEn.toLocal();
    expect(e.ocurreEn(ancla), isTrue);
    expect(e.ocurreEn(ancla.add(const Duration(days: 3))), isTrue);
    // Antes del ancla no ocurre.
    expect(e.ocurreEn(ancla.subtract(const Duration(days: 1))), isFalse);
  });

  test('copyConInicio desplaza la ocurrencia y la vuelve instancia única', () {
    final e = Evento.fromJson(_baseJson({
      'recurrencia_freq': 'diaria',
    }));
    final duracion = e.terminaEn!.difference(e.iniciaEn); // 2 h
    final nuevoInicio = DateTime.utc(2026, 6, 20, 13, 0);
    final occ = e.copyConInicio(nuevoInicio);

    expect(occ.id, e.id); // sigue apuntando al ancla (misma fila)
    expect(occ.regla, isNull); // ya es una instancia, no la serie
    expect(occ.iniciaEn, nuevoInicio);
    expect(occ.terminaEn, nuevoInicio.add(duracion));
  });
}

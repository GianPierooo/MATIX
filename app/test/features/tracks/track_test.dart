import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/tracks/domain/track.dart';

/// Tests del dominio de tracks (Fase 2): parseo del JSON, posición
/// legible, y los helpers de activos / pausados / tope.

Map<String, dynamic> _json({
  String estado = 'activo',
  String? bloque,
  int? semana,
  int? dia,
}) =>
    {
      'id': 'id-$estado-${bloque ?? ""}',
      'nombre': 'Calistenia',
      'descripcion': 'Fuerza con peso corporal',
      'estado': estado,
      'bloque_actual': bloque,
      'semana': semana,
      'dia': dia,
      'creado_en': '2026-05-01T10:00:00+00:00',
      'actualizado_en': '2026-05-10T10:00:00+00:00',
    };

void main() {
  group('Track.fromJson', () {
    test('parsea campos y estado', () {
      final t = Track.fromJson(_json(bloque: 'Bloque 3', semana: 2, dia: 4));
      expect(t.nombre, 'Calistenia');
      expect(t.estado, EstadoTrack.activo);
      expect(t.activo, isTrue);
      expect(t.bloqueActual, 'Bloque 3');
      expect(t.semana, 2);
      expect(t.dia, 4);
    });

    test('estado pausado', () {
      final t = Track.fromJson(_json(estado: 'pausado'));
      expect(t.estado, EstadoTrack.pausado);
      expect(t.activo, isFalse);
    });

    test('posicionLabel arma bloque · semana · día, o "Sin posición"', () {
      expect(
        Track.fromJson(_json(bloque: 'Bloque 3', semana: 2, dia: 4))
            .posicionLabel,
        'Bloque 3 · semana 2 · día 4',
      );
      expect(Track.fromJson(_json()).posicionLabel, 'Sin posición');
      expect(
        Track.fromJson(_json(bloque: 'Intro')).posicionLabel,
        'Intro',
      );
    });
  });

  group('helpers activos / pausados / tope', () {
    final tracks = [
      Track.fromJson(_json(estado: 'activo', bloque: 'a')),
      Track.fromJson(_json(estado: 'activo', bloque: 'b')),
      Track.fromJson(_json(estado: 'pausado', bloque: 'c')),
    ];

    test('separa activos y pausados', () {
      expect(tracksActivos(tracks).length, 2);
      expect(tracksPausados(tracks).length, 1);
    });

    test('puedeActivarOtro respeta el tope de 3', () {
      expect(puedeActivarOtro(tracks), isTrue); // 2 activos < 3
      final tres = [
        Track.fromJson(_json(estado: 'activo', bloque: '1')),
        Track.fromJson(_json(estado: 'activo', bloque: '2')),
        Track.fromJson(_json(estado: 'activo', bloque: '3')),
      ];
      expect(puedeActivarOtro(tres), isFalse); // 3 activos
    });
  });
}

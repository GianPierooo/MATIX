import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/push/domain/intensidad_notif.dart';

void main() {
  group('IntensidadNotif.fromJson', () {
    test('arranca en ALTO (intenso) para null/desconocido', () {
      expect(IntensidadNotif.fromJson(null), IntensidadNotif.intenso);
      expect(IntensidadNotif.fromJson('otro'), IntensidadNotif.intenso);
    });
    test('mapea los valores conocidos', () {
      expect(IntensidadNotif.fromJson('suave'), IntensidadNotif.suave);
      expect(IntensidadNotif.fromJson('medio'), IntensidadNotif.medio);
      expect(IntensidadNotif.fromJson('intenso'), IntensidadNotif.intenso);
      expect(IntensidadNotif.fromJson('maximo'), IntensidadNotif.maximo);
    });
  });

  group('mecanismoDe (mapeo a mecanismos Android)', () {
    test('suave: estándar, sin saltar ni persistir ni full-screen', () {
      final m = mecanismoDe(IntensidadNotif.suave);
      expect(m.canal, canalSuave);
      expect(m.headsUp, isFalse);
      expect(m.persistente, isFalse);
      expect(m.fullScreen, isFalse);
    });

    test('medio: heads-up, sin persistir', () {
      final m = mecanismoDe(IntensidadNotif.medio);
      expect(m.canal, canalAvisos);
      expect(m.headsUp, isTrue);
      expect(m.persistente, isFalse);
      expect(m.fullScreen, isFalse);
    });

    test('intenso: heads-up + persistente, sin full-screen', () {
      final m = mecanismoDe(IntensidadNotif.intenso);
      expect(m.canal, canalAvisos);
      expect(m.headsUp, isTrue);
      expect(m.persistente, isTrue);
      expect(m.fullScreen, isFalse);
    });

    test('máximo NO crítico: persistente pero SIN full-screen', () {
      final m = mecanismoDe(IntensidadNotif.maximo, critico: false);
      expect(m.canal, canalAvisos);
      expect(m.persistente, isTrue);
      expect(m.fullScreen, isFalse);
    });

    test('máximo + CRÍTICO: full-screen en el canal crítico (como alarma)', () {
      final m = mecanismoDe(IntensidadNotif.maximo, critico: true);
      expect(m.canal, canalCritico);
      expect(m.headsUp, isTrue);
      expect(m.persistente, isTrue);
      expect(m.fullScreen, isTrue);
    });

    test('solo MÁXIMO habilita full-screen, ni siquiera intenso crítico', () {
      // El crítico solo escala a full-screen en máximo: en intenso sigue sin
      // tomar la pantalla.
      expect(mecanismoDe(IntensidadNotif.intenso, critico: true).fullScreen,
          isFalse);
      expect(mecanismoDe(IntensidadNotif.medio, critico: true).fullScreen,
          isFalse);
    });
  });
}

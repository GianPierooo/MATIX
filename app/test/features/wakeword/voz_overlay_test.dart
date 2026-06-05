import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/wakeword/domain/voz_overlay.dart';

void main() {
  group('superficieParaWake (decisión overlay vs fullscreen)', () {
    test('overlay solo si habilitado + permitido + app en background', () {
      expect(
        superficieParaWake(
            overlayHabilitado: true,
            overlayPermitido: true,
            appEnPrimerPlano: false),
        SuperficieWake.overlay,
      );
    });

    test('si Matix ya está al frente → fullscreen (natural)', () {
      expect(
        superficieParaWake(
            overlayHabilitado: true,
            overlayPermitido: true,
            appEnPrimerPlano: true),
        SuperficieWake.fullscreen,
      );
    });

    test('sin permiso de overlay → degrada a fullscreen', () {
      expect(
        superficieParaWake(
            overlayHabilitado: true,
            overlayPermitido: false,
            appEnPrimerPlano: false),
        SuperficieWake.fullscreen,
      );
    });

    test('deshabilitado → fullscreen (comportamiento actual)', () {
      expect(
        superficieParaWake(
            overlayHabilitado: false,
            overlayPermitido: true,
            appEnPrimerPlano: false),
        SuperficieWake.fullscreen,
      );
    });
  });

  group('motivoDegradacion (aviso honesto)', () {
    test('explica el permiso cuando se quería overlay pero falta', () {
      final m = motivoDegradacion(
          overlayHabilitado: true,
          overlayPermitido: false,
          appEnPrimerPlano: false);
      expect(m, isNotNull);
      expect(m, contains('mostrar sobre otras apps'));
      expect(m!.contains('*'), isFalse);
    });

    test('no avisa si no se quería overlay', () {
      expect(
        motivoDegradacion(
            overlayHabilitado: false,
            overlayPermitido: false,
            appEnPrimerPlano: false),
        isNull,
      );
    });

    test('no avisa si ya estás en Matix al frente', () {
      expect(
        motivoDegradacion(
            overlayHabilitado: true,
            overlayPermitido: false,
            appEnPrimerPlano: true),
        isNull,
      );
    });
  });

  group('TransicionesOverlay (máquina de estados)', () {
    test('abrir → visible + abriendo', () {
      final s = TransicionesOverlay.abrir();
      expect(s.visible, isTrue);
      expect(s.fase, FaseOverlay.abriendo);
    });

    test('enFase avanza mientras está visible', () {
      var s = TransicionesOverlay.abrir();
      s = TransicionesOverlay.enFase(s, FaseOverlay.escuchando);
      expect(s.fase, FaseOverlay.escuchando);
      s = TransicionesOverlay.enFase(s, FaseOverlay.hablando);
      expect(s.fase, FaseOverlay.hablando);
      expect(s.visible, isTrue);
    });

    test('enFase NO resucita un overlay ya cerrado', () {
      final cerrado = TransicionesOverlay.cerrar();
      final s = TransicionesOverlay.enFase(cerrado, FaseOverlay.hablando);
      expect(s.visible, isFalse);
      expect(s, EstadoVozOverlay.inactivo);
    });

    test('cerrar y expandir dejan el overlay invisible (no persistente)', () {
      expect(TransicionesOverlay.cerrar(), EstadoVozOverlay.inactivo);
      expect(TransicionesOverlay.expandir(), EstadoVozOverlay.inactivo);
    });
  });

  group('faseOverlayDe (mapeo desde manos libres)', () {
    test('mapea las fases de la pipeline a las del overlay', () {
      expect(faseOverlayDe('escuchando'), FaseOverlay.escuchando);
      expect(faseOverlayDe('transcribiendo'), FaseOverlay.pensando);
      expect(faseOverlayDe('pensando'), FaseOverlay.pensando);
      expect(faseOverlayDe('hablando'), FaseOverlay.hablando);
      expect(faseOverlayDe('inactivo'), FaseOverlay.cerrado);
      expect(faseOverlayDe('error'), FaseOverlay.cerrado);
      expect(faseOverlayDe('cualquier_otra'), FaseOverlay.abriendo);
    });
  });
}

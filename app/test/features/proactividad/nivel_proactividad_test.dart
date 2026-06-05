import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/proactividad/domain/nivel_proactividad.dart';
import 'package:matix/features/proactividad/providers/proactividad_providers.dart';

void main() {
  group('NivelProactividad', () {
    test('fromJson tolera nulos y desconocidos → exigente', () {
      expect(NivelProactividad.fromJson('suave'), NivelProactividad.suave);
      expect(NivelProactividad.fromJson('equilibrado'),
          NivelProactividad.equilibrado);
      expect(NivelProactividad.fromJson('exigente'), NivelProactividad.exigente);
      expect(NivelProactividad.fromJson(null), NivelProactividad.exigente);
      expect(NivelProactividad.fromJson('???'), NivelProactividad.exigente);
    });

    test('toJson coincide con el name (contrato con el cerebro)', () {
      for (final n in NivelProactividad.values) {
        expect(n.toJson(), n.name);
        expect(NivelProactividad.fromJson(n.toJson()), n);
      }
    });

    test('cada nivel tiene etiqueta y descripción', () {
      for (final n in NivelProactividad.values) {
        expect(n.etiqueta, isNotEmpty);
        expect(n.descripcion, isNotEmpty);
      }
    });
  });

  group('ProactividadUiConfig', () {
    test('default es ON + exigente (proactivo y encima)', () {
      const c = ProactividadUiConfig();
      expect(c.activo, isTrue);
      expect(c.nivel, NivelProactividad.exigente);
      expect(c.leadLibreMin, 30);
    });

    test('copyWith cambia solo lo dado', () {
      const c = ProactividadUiConfig();
      final s = c.copyWith(nivel: NivelProactividad.suave);
      expect(s.nivel, NivelProactividad.suave);
      expect(s.activo, isTrue); // intacto
      final off = c.copyWith(activo: false);
      expect(off.activo, isFalse);
      expect(off.nivel, NivelProactividad.exigente);
    });
  });
}

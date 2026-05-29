import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/captura_apunte_repository.dart';

/// Tests del modelo `ApunteCapturado` (Capa 3 Paso C2).
///
/// La orquestación de voz (grabar → transcribir → capturar) vive en
/// el widget de Inicio y depende de mic/red, así que no se testea
/// como unidad. Lo que sí es lógica pura y testeable es cómo se lee
/// la respuesta del cerebro y cómo se arma la frase del snackbar.
void main() {
  group('ApunteCapturado.fromJson', () {
    test('lee la clasificación a un proyecto', () {
      final a = ApunteCapturado.fromJson({
        'id': 'abc-123',
        'titulo': 'Idea de tesis',
        'etiquetas': ['tesis', 'idea'],
        'general': false,
        'proyecto_nombre': 'Tesis',
        'curso_nombre': null,
      });
      expect(a.id, 'abc-123');
      expect(a.titulo, 'Idea de tesis');
      expect(a.etiquetas, ['tesis', 'idea']);
      expect(a.general, isFalse);
      expect(a.proyectoNombre, 'Tesis');
      expect(a.cursoNombre, isNull);
    });

    test('apunte general: sin proyecto ni curso', () {
      final a = ApunteCapturado.fromJson({
        'id': 'xyz',
        'titulo': 'algo suelto',
        'etiquetas': <String>[],
        'general': true,
      });
      expect(a.general, isTrue);
      expect(a.proyectoNombre, isNull);
      expect(a.cursoNombre, isNull);
    });

    test('coacciona id no-string a string', () {
      final a = ApunteCapturado.fromJson({
        'id': 42,
        'titulo': 't',
        'general': true,
      });
      expect(a.id, '42');
      expect(a.etiquetas, isEmpty);
    });
  });

  group('destinoLabel (copy en tú)', () {
    ApunteCapturado conDestino({String? proyecto, String? curso}) =>
        ApunteCapturado(
          id: '1',
          titulo: 't',
          etiquetas: const [],
          general: proyecto == null && curso == null,
          proyectoNombre: proyecto,
          cursoNombre: curso,
        );

    test('proyecto tiene prioridad', () {
      expect(
        conDestino(proyecto: 'Tesis', curso: 'Cálculo').destinoLabel,
        'Guardado en proyecto Tesis',
      );
    });

    test('curso cuando no hay proyecto', () {
      expect(
        conDestino(curso: 'Cálculo').destinoLabel,
        'Guardado en el curso Cálculo',
      );
    });

    test('general cuando no hay ni proyecto ni curso', () {
      expect(conDestino().destinoLabel, 'Guardado como apunte general');
    });

    test('nombre vacío cuenta como general', () {
      expect(
        conDestino(proyecto: '').destinoLabel,
        'Guardado como apunte general',
      );
    });
  });
}

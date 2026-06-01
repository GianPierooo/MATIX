import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/contacto_memoria.dart';

void main() {
  test('arma el mensaje con nombre, teléfono y correo', () {
    final m = mensajeGuardarContacto(
      nombre: 'Ana Pérez',
      telefonos: ['999111222'],
      correos: ['ana@mail.com'],
    );
    expect(m, contains('categoría personas'));
    expect(m, contains('Nombre: Ana Pérez'));
    expect(m, contains('Teléfono: 999111222'));
    expect(m, contains('Correo: ana@mail.com'));
  });

  test('ignora teléfonos/correos vacíos', () {
    final m = mensajeGuardarContacto(
      nombre: 'Beto',
      telefonos: ['', '  '],
      correos: const [],
    );
    expect(m, contains('Nombre: Beto'));
    expect(m, isNot(contains('Teléfono')));
    expect(m, isNot(contains('Correo')));
  });

  test('devuelve null si no hay nada que guardar', () {
    expect(
      mensajeGuardarContacto(nombre: '   ', telefonos: const [], correos: const []),
      isNull,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/documento_repository.dart';

void main() {
  test('DocumentoExtraido.fromJson mapea los campos', () {
    final d = DocumentoExtraido.fromJson({
      'nombre': 'silabo.pdf',
      'texto': 'TEMARIO',
      'caracteres': 7,
      'truncado': true,
    });
    expect(d.nombre, 'silabo.pdf');
    expect(d.texto, 'TEMARIO');
    expect(d.caracteres, 7);
    expect(d.truncado, isTrue);
  });

  test('DocumentoExtraido.fromJson usa defaults seguros', () {
    final d = DocumentoExtraido.fromJson({});
    expect(d.nombre, 'documento');
    expect(d.texto, '');
    expect(d.truncado, isFalse);
  });
}

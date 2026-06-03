import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/whatsapp_accion_logica.dart';

/// Tier C.1 · lógica pura del bucle de acción: decisión, verificación por paso
/// y comparación de contacto. Se testea sin device (todo es puro).

void main() {
  group('decidirSiguienteAccion', () {
    test('avanza fase por fase: verificar → escribir → confirmar → enviar → completar', () {
      var e = const EstadoFlujo();
      expect(decidirSiguienteAccion(e, 'hola').tipo, 'verificar_contacto');

      e = e.copyWith(contactoVerificado: true);
      final escribir = decidirSiguienteAccion(e, 'hola');
      expect(escribir.tipo, 'escribir');
      expect(escribir.accion!.tipo, 'set_text');
      expect(escribir.accion!.targetValor, kWhatsappEntry);
      expect(escribir.accion!.texto, 'hola');

      e = e.copyWith(textoEscrito: true);
      expect(decidirSiguienteAccion(e, 'hola').tipo, 'confirmar');

      e = e.copyWith(confirmado: true);
      final enviar = decidirSiguienteAccion(e, 'hola');
      expect(enviar.tipo, 'enviar');
      expect(enviar.accion!.tipo, 'tap');
      expect(enviar.accion!.targetValor, kWhatsappSend);

      e = e.copyWith(enviado: true);
      expect(decidirSiguienteAccion(e, 'hola').tipo, 'completar');
    });

    test('kill switch aborta en cualquier punto', () {
      final e = const EstadoFlujo(contactoVerificado: true, textoEscrito: true, killSwitch: true);
      expect(decidirSiguienteAccion(e, 'x').tipo, 'abortar');
    });

    test('tope de pasos aborta', () {
      final e = const EstadoFlujo(contactoVerificado: true, pasos: kMaxPasos);
      expect(decidirSiguienteAccion(e, 'x').tipo, 'abortar');
    });

    test('NUNCA decide enviar sin confirmar antes', () {
      // Aunque el texto esté escrito, sin confirmado el siguiente paso es
      // confirmar — jamás 'enviar'.
      final e = const EstadoFlujo(contactoVerificado: true, textoEscrito: true);
      expect(decidirSiguienteAccion(e, 'x').tipo, isNot('enviar'));
      expect(decidirSiguienteAccion(e, 'x').tipo, 'confirmar');
    });
  });

  group('contactoCoincide', () {
    test('nombre parcial calza con encabezado completo', () {
      expect(contactoCoincide(nombre: 'María', encabezado: 'María García'), isTrue);
      expect(contactoCoincide(nombre: 'maria', encabezado: 'María García'), isTrue);
    });

    test('no calza cuando es otro contacto', () {
      expect(contactoCoincide(nombre: 'María', encabezado: 'Pedro Ruiz'), isFalse);
    });

    test('encabezado vacío nunca calza (no se puede confirmar)', () {
      expect(contactoCoincide(nombre: 'María', encabezado: ''), isFalse);
    });

    test('calza por número cuando el encabezado es un teléfono', () {
      expect(
        contactoCoincide(nombre: 'Desconocido', numero: '+51 999 888 777', encabezado: '+51 999 888 777'),
        isTrue,
      );
      expect(
        contactoCoincide(nombre: 'X', numero: '999888777', encabezado: 'Juan'),
        isFalse,
      );
    });
  });

  group('verificación post-acción', () {
    test('textoQuedoEscrito: la caja debe contener el mensaje', () {
      expect(textoQuedoEscrito('hola que tal', 'hola que tal'), isTrue);
      expect(textoQuedoEscrito('Hola', 'hola'), isTrue); // normaliza
      expect(textoQuedoEscrito('hola', null), isFalse);
      expect(textoQuedoEscrito('hola', 'otra cosa'), isFalse);
    });

    test('mensajeFueEnviado: la caja queda vacía tras enviar', () {
      expect(mensajeFueEnviado(null), isTrue);
      expect(mensajeFueEnviado('   '), isTrue);
      expect(mensajeFueEnviado('todavía está acá'), isFalse);
    });
  });
}

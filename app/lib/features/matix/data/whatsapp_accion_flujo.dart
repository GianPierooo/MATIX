import 'accesibilidad_service.dart';
import 'contactos_resolver.dart';
import 'dispositivo_service.dart';
import 'whatsapp_accion_logica.dart';

/// Resultado final del flujo, para reportarle al usuario con honestidad.
class ResultadoFlujo {
  const ResultadoFlujo(this.ok, this.mensaje, this.fase);
  final bool ok;
  final String mensaje;
  final FaseWhatsapp fase;
}

/// Orquestador (impuro) del bucle de acción de WhatsApp (Tier C.1):
///   abrir chat (intent) → leer pantalla → decidir (puro) → ejecutar →
///   releer y VERIFICAR (puro) → repetir, hasta completar o abortar.
///
/// Salvaguardas vivas: gate de confirmación antes de enviar, kill switch
/// (notificación / voz / cancelar), allowlist enforced en el nativo (solo
/// WhatsApp actúa), tope de pasos + timeout, y log visible por paso. El texto
/// de pantalla es DATO: nunca cambia lo que el flujo hace.
class WhatsappAccionFlujo {
  WhatsappAccionFlujo(this._acc, this._dispositivo, this._contactos);

  final AccesibilidadService _acc;
  final DispositivoService _dispositivo;
  final ContactosResolver _contactos;

  static const _timeout = Duration(seconds: 45);

  /// [confirmar] muestra el gate (overlay) y devuelve 'enviar'|'cancelar'|
  /// 'sin_overlay'. [onLog] reporta cada paso (lo pinta la notificación).
  Future<ResultadoFlujo> ejecutar({
    required String contacto,
    required String mensaje,
    required void Function(String) onLog,
    required Future<String> Function(String resumen) confirmar,
  }) async {
    if (!await _acc.activa()) {
      return const ResultadoFlujo(false, 'inactivo', FaseWhatsapp.abortado);
    }

    // Resolver el contacto a un número (sin adivinar nunca).
    final r = await _contactos.resolver(contacto);
    switch (r.estado) {
      case 'ninguno':
        return ResultadoFlujo(false, 'No encontré a "$contacto" en tus contactos.', FaseWhatsapp.abortado);
      case 'varios':
        final lista = r.ambiguos.take(4).join(', ');
        return ResultadoFlujo(false, 'Hay varios contactos como "$contacto" ($lista). Dime cuál o pásame el número.', FaseWhatsapp.abortado);
      case 'sin_permiso':
        return ResultadoFlujo(false, 'Necesito permiso de contactos para encontrar a "$contacto", o dame el número.', FaseWhatsapp.abortado);
    }
    final numero = r.numero!;
    final nombre = r.nombre ?? contacto;

    await _acc.iniciarFlujo();
    try {
      onLog('Abriendo el chat de $nombre…');
      await _acc.actualizarFlujo('Abriendo el chat de $nombre…');
      await _dispositivo.ejecutar('abrir', {
        'objetivo': 'url',
        'valor': 'https://wa.me/${_digitos(numero)}',
      });

      var estado = const EstadoFlujo();
      final inicio = DateTime.now();

      while (true) {
        if (await _acc.estaAbortado()) {
          return const ResultadoFlujo(false, 'Listo, me detuve.', FaseWhatsapp.abortado);
        }
        if (DateTime.now().difference(inicio) > _timeout) {
          return const ResultadoFlujo(false, 'Tardó demasiado, lo dejé sin enviar.', FaseWhatsapp.abortado);
        }

        final d = decidirSiguienteAccion(estado, mensaje);
        switch (d.tipo) {
          case 'verificar_contacto':
            final header = await _esperarEncabezado();
            if (header == null) {
              return const ResultadoFlujo(false, 'No pude leer el chat. Ábrelo y reintenta.', FaseWhatsapp.abortado);
            }
            if (!contactoCoincide(nombre: nombre, numero: numero, encabezado: header)) {
              return ResultadoFlujo(false, 'El chat abierto ("$header") no es $nombre. No escribí nada.', FaseWhatsapp.abortado);
            }
            _log(onLog, 'Confirmé que es el chat de $header.');
            estado = estado.copyWith(contactoVerificado: true, pasos: estado.pasos + 1);

          case 'escribir':
            _log(onLog, 'Escribiendo el mensaje…');
            await _acc.ejecutarAccion(d.accion!.toJson());
            await _pausa();
            final leido = await _acc.leerTextoPorId(kWhatsappEntry);
            if (!textoQuedoEscrito(mensaje, leido)) {
              return const ResultadoFlujo(false, 'No pude escribir el mensaje en WhatsApp.', FaseWhatsapp.abortado);
            }
            estado = estado.copyWith(textoEscrito: true, pasos: estado.pasos + 1);

          case 'confirmar':
            final dec = await confirmar('¿Le envío a $nombre: "$mensaje"?');
            if (dec == 'enviar') {
              estado = estado.copyWith(confirmado: true, pasos: estado.pasos + 1);
            } else if (dec == 'sin_overlay') {
              return const ResultadoFlujo(false, 'No pude mostrar la confirmación. Dejé el mensaje escrito; envíalo tú.', FaseWhatsapp.abortado);
            } else {
              return const ResultadoFlujo(false, 'Lo dejé escrito y no lo envié.', FaseWhatsapp.abortado);
            }

          case 'enviar':
            _log(onLog, 'Enviando…');
            await _acc.ejecutarAccion(d.accion!.toJson());
            await _pausa();
            final leido = await _acc.leerTextoPorId(kWhatsappEntry);
            estado = estado.copyWith(enviado: true, pasos: estado.pasos + 1);
            if (!mensajeFueEnviado(leido)) {
              _log(onLog, 'Toqué enviar, pero no pude confirmar que salió.');
            }

          case 'completar':
            return ResultadoFlujo(true, 'Listo, le envié a $nombre.', FaseWhatsapp.completado);

          case 'abortar':
            return ResultadoFlujo(false, 'Me detuve: ${d.motivo}.', FaseWhatsapp.abortado);
        }
      }
    } finally {
      // El resultado lo reporta quien llama (deja el aviso final).
    }
  }

  void _log(void Function(String) onLog, String texto) {
    onLog(texto);
    _acc.actualizarFlujo(texto);
  }

  /// WhatsApp tarda en abrir el chat: reintenta leer el encabezado.
  Future<String?> _esperarEncabezado() async {
    for (var i = 0; i < 8; i++) {
      if (await _acc.estaAbortado()) return null;
      final h = await _acc.leerTextoPorId(kWhatsappTitulo);
      if (h != null && h.trim().isNotEmpty) return h.trim();
      await _pausa(ms: 400);
    }
    return null;
  }

  Future<void> _pausa({int ms = 300}) => Future<void>.delayed(Duration(milliseconds: ms));

  String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');
}

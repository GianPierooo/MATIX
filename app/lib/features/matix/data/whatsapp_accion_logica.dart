/// Lógica PURA del bucle de acción de WhatsApp (Tier C.1).
///
/// Sin Flutter ni canales: decide la siguiente acción, verifica que cada paso
/// haya surtido efecto y compara el contacto del chat abierto contra el pedido.
/// Por ser pura se testea directo, sin device. El bucle (impuro) que lee la
/// pantalla y ejecuta las acciones vive en `whatsapp_accion_flujo.dart`.
library;

/// viewIds estables de WhatsApp que usa el flujo (pueden cambiar entre
/// versiones de WhatsApp; es el punto a revisar si algo deja de calzar).
const String kWhatsappEntry = 'com.whatsapp:id/entry';
const String kWhatsappSend = 'com.whatsapp:id/send';
const String kWhatsappTitulo = 'com.whatsapp:id/conversation_contact_name';

/// Tope de pasos del bucle: salvaguarda contra encadenar acciones sin fin.
const int kMaxPasos = 12;

enum FaseWhatsapp {
  verificandoContacto,
  escribiendo,
  confirmando,
  enviando,
  completado,
  abortado,
}

/// Estado observado del flujo. El bucle lo actualiza tras leer la pantalla; la
/// decisión es función pura de este estado.
class EstadoFlujo {
  const EstadoFlujo({
    this.contactoVerificado = false,
    this.textoEscrito = false,
    this.confirmado = false,
    this.enviado = false,
    this.pasos = 0,
    this.killSwitch = false,
  });

  final bool contactoVerificado;
  final bool textoEscrito;
  final bool confirmado;
  final bool enviado;
  final int pasos;
  final bool killSwitch;

  EstadoFlujo copyWith({
    bool? contactoVerificado,
    bool? textoEscrito,
    bool? confirmado,
    bool? enviado,
    int? pasos,
    bool? killSwitch,
  }) =>
      EstadoFlujo(
        contactoVerificado: contactoVerificado ?? this.contactoVerificado,
        textoEscrito: textoEscrito ?? this.textoEscrito,
        confirmado: confirmado ?? this.confirmado,
        enviado: enviado ?? this.enviado,
        pasos: pasos ?? this.pasos,
        killSwitch: killSwitch ?? this.killSwitch,
      );
}

/// Acción estructurada para el servicio de accesibilidad.
class AccionUi {
  const AccionUi({required this.tipo, this.targetPor, this.targetValor, this.texto});
  final String tipo; // 'set_text' | 'tap'
  final String? targetPor; // 'id' | 'texto' | 'desc'
  final String? targetValor;
  final String? texto;

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        if (targetPor != null) 'target': {'por': targetPor, 'valor': targetValor},
        if (texto != null) 'texto': texto,
      };
}

/// Lo que el bucle debe hacer ahora.
class Decision {
  const Decision(this.tipo, {this.accion, this.motivo = ''});
  final String tipo; // verificar_contacto|escribir|confirmar|enviar|completar|abortar
  final AccionUi? accion;
  final String motivo;
}

/// Decide la siguiente acción a partir del estado observado. Determinística y
/// pura: el «modelo» que decide el paso es esta máquina de estados (segura para
/// la primera acción); el modelo del cerebro aporta la tarea (contacto+mensaje).
Decision decidirSiguienteAccion(
  EstadoFlujo estado,
  String mensaje, {
  int maxPasos = kMaxPasos,
}) {
  if (estado.killSwitch) return const Decision('abortar', motivo: 'detenido por el usuario');
  if (estado.pasos >= maxPasos) return const Decision('abortar', motivo: 'tope de pasos');
  if (!estado.contactoVerificado) {
    return const Decision('verificar_contacto', motivo: 'confirmar el chat antes de escribir');
  }
  if (!estado.textoEscrito) {
    return Decision(
      'escribir',
      accion: AccionUi(tipo: 'set_text', targetPor: 'id', targetValor: kWhatsappEntry, texto: mensaje),
      motivo: 'escribir el mensaje en la caja',
    );
  }
  if (!estado.confirmado) {
    return const Decision('confirmar', motivo: 'gate de envío: pedir confirmación');
  }
  if (!estado.enviado) {
    return const Decision(
      'enviar',
      accion: AccionUi(tipo: 'tap', targetPor: 'id', targetValor: kWhatsappSend),
      motivo: 'tap de enviar (ya confirmado)',
    );
  }
  return const Decision('completar', motivo: 'mensaje enviado');
}

/// ¿El chat abierto corresponde al contacto pedido? Compara el encabezado del
/// chat contra el nombre (y el número, si lo hay). Si no se puede confirmar,
/// devuelve false → el bucle ABORTA (nunca escribe en el chat equivocado).
bool contactoCoincide({
  required String nombre,
  String? numero,
  required String encabezado,
}) {
  final h = _norm(encabezado);
  if (h.isEmpty) return false;

  // Por número: si el encabezado es un teléfono, comparar los últimos dígitos.
  if (numero != null) {
    final dh = _digitos(encabezado);
    final dn = _digitos(numero);
    if (dn.length >= 7 && dh.length >= 7) {
      final cola = dn.length <= 8 ? dn : dn.substring(dn.length - 8);
      if (dh.contains(cola)) return true;
    }
  }

  final p = _norm(nombre);
  if (p.isEmpty) return false;
  // El encabezado guardado suele ser el nombre completo; el pedido, una parte.
  return h.contains(p) || p.contains(h);
}

/// Tras `set_text`: el texto de la caja debe contener el mensaje esperado.
bool textoQuedoEscrito(String esperado, String? leido) {
  if (leido == null) return false;
  return _norm(leido).contains(_norm(esperado));
}

/// Tras el tap de enviar: la caja de texto debe quedar vacía (se envió).
bool mensajeFueEnviado(String? cajaLeida) =>
    cajaLeida == null || cajaLeida.trim().isEmpty;

String _norm(String s) {
  var r = s.toLowerCase().trim();
  const conAcento = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const sinAcento = 'aaaaaeeeeiiiiooooouuuun';
  for (var i = 0; i < conAcento.length; i++) {
    r = r.replaceAll(conAcento[i], sinAcento[i]);
  }
  return r.replaceAll(RegExp(r'\s+'), ' ');
}

String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');
